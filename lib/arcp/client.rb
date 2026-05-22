# frozen_string_literal: true

require 'async'
require 'async/queue'
require 'time'

require_relative 'envelope'
require_relative 'errors'
require_relative 'message_types'
require_relative 'session'
require_relative 'job'
require_relative 'lease'
require_relative 'trace'
require_relative 'ids'
require_relative 'clock'

module Arcp
  # ARCP client: opens a session over a transport, submits jobs,
  # consumes events, and provides cursored job listings.
  #
  # @example Connect over an in-memory transport pair
  #   server_t, client_t = Arcp::Transport::MemoryTransport.pair
  #   Sync do
  #     client = Arcp::Client.open(
  #       transport: client_t,
  #       auth: { 'scheme' => 'bearer', 'token' => 'demo' }
  #     )
  #     handle = client.submit_job(agent: 'echo', input: { 'msg' => 'hi' })
  #     handle.subscribe(client: client).each { |ev| puts ev.kind }
  #     client.close
  #   end
  class Client
    attr_reader :session, :transport

    def self.open(transport:, auth:, client_name: 'arcp-ruby', client_version: Arcp::VERSION,
                  capabilities: nil, resume: nil, clock: Arcp::SystemClock.new)
      client = new(transport: transport, clock: clock)
      client.handshake!(auth: auth, client_name: client_name, client_version: client_version,
                        capabilities: capabilities, resume: resume)
      client
    end

    def initialize(transport:, clock: Arcp::SystemClock.new)
      @transport = transport
      @clock = clock
      @session = nil
      @inbox = Async::Queue.new
      @pending = {}
      @job_streams = {}
      @job_results = {}
      @result_waiters = {}
      @reader_task = nil
      @heartbeat_task = nil
      @next_outbound_seq = 0
      @inbound_seq = 0
      @closed = false
      @mutex = Mutex.new
    end

    def handshake!(auth:, client_name:, client_version:, capabilities: nil, resume: nil)
      caps = capabilities || Arcp::Session::CapabilitySet.local
      session_id = Arcp::Ids.session_id
      hello = Arcp::Session::Hello.new(
        client_name: client_name, client_version: client_version,
        auth: auth, capabilities: caps, resume: resume
      )
      env = Arcp::Envelope.build(
        type: Arcp::MessageTypes::SESSION_HELLO,
        session_id: session_id,
        payload: hello.to_h
      )
      @transport.send(env)

      welcome_env = @transport.receive
      raise Arcp::Errors::ProtocolViolation, 'transport closed before welcome' if welcome_env.nil?

      case welcome_env.type
      when Arcp::MessageTypes::SESSION_WELCOME
        welcome = Arcp::Session::Welcome.from_h(welcome_env.payload)
        effective = caps.intersect(welcome.capabilities)
        @session = Arcp::Session::Info.new(
          id: welcome_env.session_id,
          runtime_version: welcome.runtime_version,
          capabilities: effective,
          agents: welcome.capabilities.agents,
          heartbeat_interval_sec: welcome.heartbeat_interval_sec,
          resume_token: welcome.resume_token,
          resume_window_sec: welcome.resume_window_sec
        )
      when Arcp::MessageTypes::SESSION_ERROR
        err = Arcp::Session::SessionError.from_h(welcome_env.payload)
        raise Arcp::Errors.for(err.code, message: err.message, details: err.details || {})
      else
        raise Arcp::Errors::ProtocolViolation, "expected session.welcome, got #{welcome_env.type}"
      end

      start_reader!
      if @session.supports?(Arcp::Session::Feature::HEARTBEAT) && @session.heartbeat_interval_sec
        start_heartbeat!
      end
      @session
    end

    def list_jobs(status: nil, agent: nil, created_after: nil, limit: nil, cursor: nil)
      require_feature!(Arcp::Session::Feature::LIST_JOBS)

      Enumerator.new do |yielder|
        next_cursor = cursor
        loop do
          payload = Arcp::Session::ListJobs.new(
            filter: { 'status' => status, 'agent' => agent, 'created_after' => created_after }.compact,
            limit: limit,
            cursor: next_cursor
          ).to_h
          response = request(type: Arcp::MessageTypes::SESSION_LIST_JOBS,
                             expect: Arcp::MessageTypes::SESSION_JOBS,
                             payload: payload)
          jobs = Arcp::Session::JobsResponse.from_h(response.payload)
          jobs.jobs.each { |j| yielder << Arcp::Job::Summary.from_h(j) }
          next_cursor = jobs.next_cursor
          break if next_cursor.nil?
        end
      end.lazy
    end

    def submit_job(agent:, input: nil, lease_request: nil, lease_constraints: nil,
                   idempotency_key: nil, max_runtime_sec: nil)
      lease_constraints&.validate!

      submit = Arcp::Job::Submit.new(
        agent: agent, input: input,
        lease_request: lease_request, lease_constraints: lease_constraints,
        idempotency_key: idempotency_key, max_runtime_sec: max_runtime_sec
      )
      accepted_env = request(
        type: Arcp::MessageTypes::JOB_SUBMIT,
        expect: Arcp::MessageTypes::JOB_ACCEPTED,
        payload: submit.to_h
      )
      accepted = Arcp::Job::Accepted.from_h(accepted_env.payload)
      Arcp::Job::Handle.new(
        job_id: accepted.job_id, agent: accepted.agent,
        submitted_at: accepted.accepted_at,
        lease: accepted.lease,
        credentials: accepted.credentials
      )
    end

    def subscribe_job(job_id:, from_event_seq: nil, history: false)
      queue = @mutex.synchronize { @job_streams[job_id] ||= Async::Queue.new }

      if @session.supports?(Arcp::Session::Feature::SUBSCRIBE) && from_event_seq
        send_envelope(type: Arcp::MessageTypes::JOB_SUBSCRIBE,
                      job_id: job_id,
                      payload: Arcp::Job::Subscribe.new(job_id: job_id, from_event_seq: from_event_seq,
                                                        history: history).to_h)
      end

      Enumerator.new do |yielder|
        loop do
          item = queue.dequeue
          break if item.nil? || item == :__arcp_end__

          yielder << item
        end
      end
    end

    def cancel_job(job_id:, reason: nil)
      send_envelope(type: Arcp::MessageTypes::JOB_CANCEL,
                    job_id: job_id,
                    payload: Arcp::Job::Cancel.new(job_id: job_id, reason: reason).to_h)
    end

    def get_result(job_id:)
      env = @mutex.synchronize { @job_results[job_id] }
      if env.nil?
        queue = Async::Queue.new
        @mutex.synchronize { @result_waiters[job_id] = queue }
        env = queue.dequeue
      end
      case env.type
      when Arcp::MessageTypes::JOB_RESULT
        Arcp::Job::Result.from_h(env.payload)
      when Arcp::MessageTypes::JOB_ERROR
        raise Arcp::Job::JobError.from_h(env.payload).to_exception
      else
        raise Arcp::Errors::ProtocolViolation, "unexpected #{env.type}"
      end
    end

    def ack(seq)
      require_feature!(Arcp::Session::Feature::ACK)
      send_envelope(type: Arcp::MessageTypes::SESSION_ACK,
                    payload: Arcp::Session::Ack.new(last_processed_seq: seq).to_h)
    end

    def send_envelope(type:, payload:, job_id: nil)
      raise Arcp::Errors::Internal, 'session not open' unless @session
      raise IOError, 'client closed' if @closed

      env = Arcp::Envelope.build(
        type: type, session_id: @session.id,
        trace_id: Arcp::Trace.current.trace_id,
        job_id: job_id, payload: payload
      )
      @transport.send(env)
      env
    end

    def close(reason: nil)
      return if @closed

      @closed = true
      begin
        send_envelope(type: Arcp::MessageTypes::SESSION_BYE,
                      payload: Arcp::Session::Bye.new(reason: reason).to_h)
      rescue StandardError
        nil
      end
      @heartbeat_task&.stop
      @reader_task&.stop
      @transport.close(reason: reason)
      drain_streams
      nil
    end

    private

    def require_feature!(feature)
      return if @session.supports?(feature)

      raise Arcp::Errors::UnnegotiatedFeature, "feature not negotiated: #{feature}"
    end

    def request(type:, expect:, payload:)
      env = send_envelope(type: type, payload: payload)
      queue = Async::Queue.new
      @mutex.synchronize { @pending[env.id] = [expect, queue] }
      response = queue.dequeue
      raise Arcp::Errors::ProtocolViolation, 'transport closed' if response.nil?

      case response.type
      when expect
        response
      when Arcp::MessageTypes::JOB_ERROR
        raise Arcp::Job::JobError.from_h(response.payload).to_exception
      when Arcp::MessageTypes::SESSION_ERROR
        err = Arcp::Session::SessionError.from_h(response.payload)
        raise Arcp::Errors.for(err.code, message: err.message, details: err.details || {})
      else
        raise Arcp::Errors::ProtocolViolation, "expected #{expect}, got #{response.type}"
      end
    end

    def start_reader!
      @reader_task = Async do |_task|
        loop do
          env = @transport.receive
          break if env.nil?

          dispatch(env)
        end
      rescue Async::Stop
        nil
      ensure
        drain_streams
      end
    end

    def start_heartbeat!
      interval = @session.heartbeat_interval_sec
      @heartbeat_task = Async do |task|
        loop do
          task.sleep(interval)
          next if @closed

          send_envelope(
            type: Arcp::MessageTypes::SESSION_PING,
            payload: Arcp::Session::Ping.new(nonce: Arcp::Ids.envelope_id, sent_at: @clock.now.iso8601).to_h
          )
        rescue StandardError
          nil
        end
      rescue Async::Stop
        nil
      end
    end

    def dispatch(env)
      @inbound_seq = env.event_seq if env.event_seq

      case env.type
      when Arcp::MessageTypes::JOB_EVENT
        feed_job_stream(env)
      when Arcp::MessageTypes::JOB_RESULT, Arcp::MessageTypes::JOB_ERROR
        feed_pending(env) # may satisfy a pending submit/get_result waiter
        feed_result(env)
        feed_job_stream(env, end_stream: true)
      when Arcp::MessageTypes::SESSION_PING
        ping = Arcp::Session::Ping.from_h(env.payload)
        send_envelope(type: Arcp::MessageTypes::SESSION_PONG,
                      payload: Arcp::Session::Pong.new(ping_nonce: ping.nonce,
                                                       received_at: @clock.now.iso8601).to_h)
      when Arcp::MessageTypes::SESSION_PONG
        # noop — receipt of any inbound resets timer (implicit)
      else
        feed_pending(env)
      end
    end

    def feed_job_stream(env, end_stream: false)
      queue = @mutex.synchronize { @job_streams[env.job_id] ||= Async::Queue.new }

      queue.enqueue(Arcp::Job::Event.from_h(env.payload)) if env.type == Arcp::MessageTypes::JOB_EVENT

      queue.enqueue(:__arcp_end__) if end_stream
    end

    def feed_result(env)
      waiter = @mutex.synchronize do
        @job_results[env.job_id] = env
        @result_waiters.delete(env.job_id)
      end
      waiter&.enqueue(env)
    end

    def feed_pending(env)
      reply_to = env.payload.is_a?(Hash) ? env.payload['reply_to'] : nil
      key = reply_to || @mutex.synchronize do
        @pending.keys.find do |k|
          @pending[k].is_a?(Array) && @pending[k][0] == env.type
        end
      end
      return unless key

      pair = @mutex.synchronize { @pending.delete(key) }
      pair&.last&.enqueue(env)
    end

    def drain_streams
      @mutex.synchronize do
        @job_streams.each_value { |q| q.enqueue(:__arcp_end__) }
        @job_streams.clear
        @pending.each_value do |v|
          (v.is_a?(Array) ? v[1] : v).enqueue(nil)
        end
        @pending.clear
        @result_waiters.each_value { |q| q.enqueue(nil) }
        @result_waiters.clear
      end
    end
  end
end
