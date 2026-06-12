# frozen_string_literal: true

require 'async'
require 'async/queue'
require 'time'

module Arcp
  module Runtime
    # Per-connection runtime actor. Owns one transport, drives the
    # hello/welcome handshake, dispatches inbound envelopes, and serves
    # as the outbox queue subscriptions fan out into.
    class SessionActor
      attr_reader :session_id, :principal, :outbox

      def initialize(runtime:, transport:)
        @runtime = runtime
        @transport = transport
        @session_id = nil
        @principal = nil
        @outbox = Async::Queue.new
        @last_processed_seq = 0
        @capabilities = nil
        @resume_token = nil
        @heartbeat_task = nil
        @writer_task = nil
        @closed = false
      end

      def run
        Async do |task|
          envelope = @transport.receive
          return if envelope.nil?

          handshake(envelope)
          spawn_writer(task)
          spawn_heartbeat(task)
          loop_inbound(task)
        ensure
          close_session
        end
      end

      def send_envelope(envelope)
        @outbox.enqueue(envelope)
      end

      private

      def handshake(envelope)
        unless envelope.type == Arcp::MessageTypes::SESSION_HELLO
          raise Arcp::Errors::ProtocolViolation, "expected session.hello, got #{envelope.type}"
        end

        hello = Arcp::Session::Hello.from_h(envelope.payload)
        authenticate!(hello, envelope)
        @capabilities = hello.capabilities.intersect(@runtime.local_capabilities(agents_inventory: true))
        replay_envelopes = bind_session(hello, envelope)

        send_welcome
        @runtime.register_session(@session_id, self)
        replay_envelopes.each { |e| send_envelope(e) }
      rescue Arcp::Error
        raise
      rescue StandardError => e
        send_session_error(envelope&.session_id || Arcp::Ids.session_id,
                           code: 'INTERNAL_ERROR', message: e.message)
        raise
      end

      def authenticate!(hello, envelope)
        token = hello.auth.is_a?(Hash) ? (hello.auth['token'] || hello.auth[:token]) : nil
        @principal = @runtime.auth_verifier.verify(token)
        return unless @principal.nil?

        send_session_error(envelope.session_id, code: 'UNAUTHENTICATED', message: 'invalid bearer token')
        raise Arcp::Errors::Unauthenticated, 'invalid bearer token'
      end

      def bind_session(hello, envelope)
        resume_payload = normalize_resume(hello.resume)
        return perform_resume(resume_payload, envelope: envelope) if resume_payload

        @session_id = envelope.session_id
        @resume_token = Arcp::Ids.resume_token
        @runtime.resume_registry.register(
          token: @resume_token, session_id: @session_id,
          principal_id: @principal.id, last_processed_seq: 0
        )
        []
      end

      def send_welcome
        welcome = Arcp::Session::Welcome.new(
          runtime_name: @runtime.name,
          runtime_version: @runtime.version,
          capabilities: @capabilities,
          heartbeat_interval_sec: @runtime.heartbeat_interval_sec,
          resume_token: @resume_token,
          resume_window_sec: @runtime.resume_window_sec
        )
        out = Arcp::Envelope.build(
          type: Arcp::MessageTypes::SESSION_WELCOME,
          session_id: @session_id,
          payload: welcome.to_h
        )
        @transport.send(out)
      end

      def normalize_resume(resume)
        return nil if resume.nil?

        h = resume.is_a?(Hash) ? resume.transform_keys(&:to_s) : {}
        token = h['token']
        return nil if token.nil? || token.to_s.empty?

        { 'token' => token, 'last_event_seq' => h['last_event_seq'] }
      end

      def perform_resume(resume_payload, envelope:)
        token = resume_payload['token']
        entry = @runtime.resume_registry.lookup(token)
        if entry.nil?
          send_session_error(envelope.session_id,
                             code: 'RESUME_WINDOW_EXPIRED',
                             message: 'resume token unknown or expired')
          raise Arcp::Errors::ResumeWindowExpired, 'resume token unknown or expired'
        end

        unless entry.principal_id == @principal.id
          send_session_error(envelope.session_id,
                             code: 'UNAUTHENTICATED',
                             message: 'resume token does not match authenticated principal')
          raise Arcp::Errors::Unauthenticated, 'resume token does not match authenticated principal'
        end

        @session_id = entry.session_id
        @resume_token = token
        last_processed_seq = resume_payload['last_event_seq'] || entry.last_processed_seq || 0
        @last_processed_seq = last_processed_seq
        @runtime.resume_registry.mark_reconnected(token)
        @runtime.subscription_manager.rebind_session(@session_id, @outbox)
        # Replay every envelope with event_seq > last_processed_seq.
        @runtime.event_log.replay(@session_id, from_event_seq: last_processed_seq + 1)
      end

      def send_session_error(session_id, code:, message:)
        err = Arcp::Session::SessionError.new(code: code, message: message,
                                              retryable: false, details: {})
        env = Arcp::Envelope.build(
          type: Arcp::MessageTypes::SESSION_ERROR,
          session_id: session_id, payload: err.to_h
        )
        @transport.send(env)
      rescue StandardError
        nil
      end

      def spawn_writer(parent)
        @writer_task = parent.async do
          loop do
            env = @outbox.dequeue
            break if env.nil? || env == :__arcp_close__

            @transport.send(env)
          end
        rescue Async::Stop, IOError
          nil
        end
      end

      def spawn_heartbeat(parent)
        return unless @capabilities.supports?(Arcp::Session::Feature::HEARTBEAT)
        return if @runtime.heartbeat_interval_sec.nil?

        @heartbeat_task = parent.async do |t|
          loop do
            t.sleep(@runtime.heartbeat_interval_sec)
            ping = Arcp::Session::Ping.new(nonce: Arcp::Ids.envelope_id,
                                           sent_at: @runtime.clock.now.iso8601)
            send_envelope(Arcp::Envelope.build(
                            type: Arcp::MessageTypes::SESSION_PING,
                            session_id: @session_id, payload: ping.to_h
                          ))
          end
        rescue Async::Stop
          nil
        end
      end

      def loop_inbound(_parent)
        loop do
          begin
            env = @transport.receive
          rescue Arcp::Error => e
            # A malformed envelope (bad arcp version / trace_id / schema) is a
            # per-message error per spec §12, not grounds for tearing down an
            # authenticated session. Surface it and keep serving the session.
            send_session_error(@session_id, code: e.code, message: e.message)
            next
          end
          break if env.nil?

          dispatch(env)
        end
      end

      def dispatch(env)
        case env.type
        when Arcp::MessageTypes::SESSION_BYE
          close_session
        when Arcp::MessageTypes::SESSION_PING
          ping = Arcp::Session::Ping.from_h(env.payload)
          send_envelope(Arcp::Envelope.build(
                          type: Arcp::MessageTypes::SESSION_PONG,
                          session_id: @session_id,
                          payload: Arcp::Session::Pong.new(ping_nonce: ping.nonce,
                                                           received_at: @runtime.clock.now.iso8601).to_h
                        ))
        when Arcp::MessageTypes::SESSION_PONG
          nil
        when Arcp::MessageTypes::SESSION_ACK
          ack = Arcp::Session::Ack.from_h(env.payload)
          @runtime.event_log.evict_up_to(@session_id, ack.last_processed_seq)
          @last_processed_seq = ack.last_processed_seq
        when Arcp::MessageTypes::SESSION_LIST_JOBS
          handle_list_jobs(env)
        when Arcp::MessageTypes::JOB_SUBMIT
          handle_submit(env)
        when Arcp::MessageTypes::JOB_CANCEL
          handle_cancel(env)
        when Arcp::MessageTypes::JOB_SUBSCRIBE
          handle_subscribe(env)
        when Arcp::MessageTypes::JOB_UNSUBSCRIBE
          handle_unsubscribe(env)
        end
        # forward-compat: unknown wire types fall through silently.
      rescue Arcp::Error => e
        reply_error(env, e)
      rescue KeyError, TypeError, ArgumentError => e
        # A missing/invalid required field in a per-message decoder (e.g.
        # `Hash#fetch` raising KeyError on a missing `agent`) is a schema
        # violation, not session-fatal. Reply INVALID_REQUEST and continue.
        reply_error(env, Arcp::Errors::InvalidRequest.new(e.message))
      rescue StandardError => e
        reply_error(env, Arcp::Errors::Internal.new(e.message))
      end

      def handle_list_jobs(env)
        unless @capabilities.supports?(Arcp::Session::Feature::LIST_JOBS)
          raise Arcp::Errors::ProtocolViolation, 'list_jobs not negotiated'
        end

        req = Arcp::Session::ListJobs.from_h(env.payload)
        response = @runtime.job_manager.list(
          principal_id: @principal.id,
          filter: req.filter, limit: req.limit || 50, cursor: req.cursor
        )
        send_envelope(Arcp::Envelope.build(
                        type: Arcp::MessageTypes::SESSION_JOBS,
                        session_id: @session_id,
                        payload: response.to_h.merge('reply_to' => env.id)
                      ))
      end

      def handle_submit(env)
        submit = Arcp::Job::Submit.from_h(env.payload)
        submit.lease_constraints&.validate!
        result = @runtime.job_manager.submit(
          submit: submit, principal_id: @principal.id,
          session_id: @session_id, session_actor: self
        )
        if result.is_a?(Array)
          job_id, resolved_agent, lease, credentials, accepted_at = result
          accepted = Arcp::Job::Accepted.new(
            job_id: job_id, agent: resolved_agent,
            accepted_at: accepted_at,
            lease: lease,
            credentials: credentials
          )
        else
          job_id = result
          record = @runtime.job_manager.lookup(job_id)
          accepted = Arcp::Job::Accepted.new(
            job_id: job_id, agent: record.agent,
            accepted_at: record.created_at,
            lease: @runtime.lease_manager.get(job_id),
            credentials: nil
          )
        end
        send_envelope(Arcp::Envelope.build(
                        type: Arcp::MessageTypes::JOB_ACCEPTED,
                        session_id: @session_id, job_id: accepted.job_id,
                        payload: accepted.to_h.merge('reply_to' => env.id)
                      ))
      end

      def handle_cancel(env)
        cancel = Arcp::Job::Cancel.from_h(env.payload)
        @runtime.job_manager.cancel(
          job_id: cancel.job_id, principal_id: @principal.id, reason: cancel.reason
        )
      end

      def handle_subscribe(env)
        unless @capabilities.supports?(Arcp::Session::Feature::SUBSCRIBE)
          raise Arcp::Errors::ProtocolViolation, 'subscribe not negotiated'
        end

        sub = Arcp::Job::Subscribe.from_h(env.payload)
        @runtime.subscription_manager.attach(sub.job_id, @principal.id, @session_id, @outbox)

        if sub.history
          replay = @runtime.event_log.replay_job(sub.job_id, from_event_seq: sub.from_event_seq)
          replay.each { |e| send_envelope(e) }
        end

        subscribed = Arcp::Job::Subscribed.new(
          job_id: sub.job_id, subscribed_from: sub.from_event_seq || 0
        )
        send_envelope(Arcp::Envelope.build(
                        type: Arcp::MessageTypes::JOB_SUBSCRIBED,
                        session_id: @session_id, job_id: sub.job_id,
                        payload: subscribed.to_h.merge('reply_to' => env.id)
                      ))
      end

      def handle_unsubscribe(env)
        unsub = Arcp::Job::Unsubscribe.from_h(env.payload)
        @runtime.subscription_manager.detach(unsub.job_id, @session_id)
      end

      def reply_error(env, error)
        if env&.job_id
          job_err = Arcp::Job::JobError.new(
            job_id: env.job_id, final_status: 'error',
            code: error.code, message: error.message,
            retryable: error.retryable?, details: error.details || {}
          )
          send_envelope(Arcp::Envelope.build(
                          type: Arcp::MessageTypes::JOB_ERROR,
                          session_id: @session_id, job_id: env.job_id,
                          payload: job_err.to_h.merge('reply_to' => env.id)
                        ))
          return
        end

        err = Arcp::Session::SessionError.new(
          code: error.code, message: error.message,
          retryable: error.retryable?, details: error.details || {}
        )
        payload = err.to_h
        payload['reply_to'] = env.id if env
        send_envelope(Arcp::Envelope.build(
                        type: Arcp::MessageTypes::SESSION_ERROR,
                        session_id: @session_id || env&.session_id || '',
                        payload: payload
                      ))
      end

      def close_session
        return if @closed

        @closed = true
        @heartbeat_task&.stop
        @writer_task&.stop
        @outbox.enqueue(:__arcp_close__)
        @transport.close
        if @session_id
          @runtime.deregister_session(@session_id)
          # Drop this session's subscription rows so fanout for jobs that
          # outlive the connection stops enqueueing into the dead outbox.
          # A resuming session re-binds a fresh outbox via rebind_session.
          @runtime.subscription_manager.detach_session(@session_id)
        end
        return unless @resume_token

        @runtime.resume_registry.mark_disconnected(
          @resume_token, last_processed_seq: @last_processed_seq
        )
      end
    end
  end
end
