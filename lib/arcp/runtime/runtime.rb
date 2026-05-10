# frozen_string_literal: true

require 'logger'
require 'async'

require 'arcp/auth/auth_scheme'
require 'arcp/capabilities'
require 'arcp/envelope'
require 'arcp/error'
require 'arcp/ids'
require 'arcp/runtime/session'
require 'arcp/store/event_log'
require 'arcp/version'

module Arcp
  module Runtime
    # ARCP runtime — accepts client connections, drives session
    # handshakes, dispatches to per-session handlers, and persists
    # events to a SQLite-backed event log.
    #
    # Phase 2 surface: handshake + capability negotiation. Subsequent
    # phases bolt on job, stream, subscription, artifact, and
    # permission management.
    class Runtime
      DEFAULT_RUNTIME_IDENTITY = {
        kind: 'arcp-ruby',
        version: Arcp::IMPL_VERSION,
        fingerprint: 'sha256:dev',
        trust_level: 'trusted'
      }.freeze

      DEFAULT_CAPABILITIES = {
        streaming: true,
        durable_jobs: true,
        checkpoints: false,
        binary_streams: false,
        agent_handoff: false,
        human_input: true,
        artifacts: true,
        subscriptions: true,
        scheduled_jobs: false,
        anonymous: false,
        interrupt: true,
        heartbeat_interval_seconds: 30,
        heartbeat_recovery: 'fail',
        binary_encoding: ['base64']
      }.freeze

      attr_reader :event_log, :logger, :capabilities, :identity, :sessions

      # @param schemes [Array<#authenticate>] auth scheme handlers
      # @param identity [Hash] runtime identity block
      # @param capabilities [Hash]
      # @param event_log [Arcp::Store::EventLog]
      # @param logger [Logger]
      # @param clock [#now]
      def initialize(schemes: [], identity: DEFAULT_RUNTIME_IDENTITY,
                     capabilities: DEFAULT_CAPABILITIES, event_log: nil,
                     logger: Logger.new(IO::NULL), clock: Time)
        @schemes = schemes.to_h { |s| [s.scheme_name, s] }.freeze
        @identity = identity.freeze
        @capabilities = capabilities.freeze
        @event_log = event_log || Store::EventLog.new
        @logger = logger
        @clock = clock
        @sessions = {}
        @sessions_mutex = Mutex.new
      end

      # Serve a single transport connection until it closes.
      # The caller is responsible for accepting connections; for
      # tests, pair an `Arcp::Transport::Memory` and pass the
      # runtime side here.
      #
      # @param transport [#send_envelope, #receive_envelope, #closed?]
      # @return [void]
      def serve(transport)
        session_id = SessionId.random
        negotiator = SessionNegotiator.new(
          session_id: session_id,
          runtime_identity: @identity,
          runtime_capabilities: @capabilities,
          schemes: @schemes
        )
        record = drive_handshake(transport, session_id, negotiator)
        return unless record

        register_session(record)
        dispatch_loop(transport, record)
      ensure
        @sessions_mutex.synchronize { @sessions.delete(session_id) if session_id }
      end

      # @api private
      def register_session(record)
        @sessions_mutex.synchronize { @sessions[record.session_id.value] = record }
      end

      # @api private
      def lookup_session(session_id)
        key = session_id.respond_to?(:value) ? session_id.value : session_id
        @sessions_mutex.synchronize { @sessions[key] }
      end

      private

      def drive_handshake(transport, session_id, negotiator)
        loop do
          envelope = transport.receive_envelope
          return nil if envelope.nil?

          @event_log.append(envelope)
          result = negotiator.receive(envelope)
          (result[:outbound] || []).each do |payload|
            sent = build_outbound(envelope, payload, session_id)
            @event_log.append(sent)
            transport.send_envelope(sent)
          end
          return result[:record] if result[:record]
          return nil if negotiator.state == :closed
        end
      end

      def dispatch_loop(transport, record)
        loop do
          envelope = transport.receive_envelope
          break if envelope.nil?

          @event_log.append(envelope)
          dispatch(envelope, transport, record)
        end
      end

      def dispatch(envelope, transport, record)
        case envelope.payload
        in Messages::Session::Close
          @logger.info('arcp.runtime') { "session closed: #{record.session_id.value}" }
          transport.close
        in Messages::Control::Ping
          send_pong(envelope, transport, record)
        else
          send_unimplemented(envelope, transport, record)
        end
      end

      def send_pong(envelope, transport, record)
        pong = Messages::Control::Pong.new(received_at: @clock.now.utc.iso8601(6))
        sent = build_outbound(envelope, pong, record.session_id, correlation_id: envelope.id)
        @event_log.append(sent)
        transport.send_envelope(sent)
      end

      def send_unimplemented(envelope, transport, record)
        nack = Messages::Control::Nack.new(
          code: ErrorCode::UNIMPLEMENTED,
          message: "type not implemented in v0.1: #{envelope.type}",
          details: { type: envelope.type },
          retryable: false
        )
        sent = build_outbound(envelope, nack, record.session_id, correlation_id: envelope.id)
        @event_log.append(sent)
        transport.send_envelope(sent)
      end

      def build_outbound(inbound, payload, session_id, correlation_id: nil)
        Envelope.new(
          arcp: Arcp::PROTOCOL_VERSION,
          id: MessageId.random,
          type: payload.class.type_name,
          timestamp: @clock.now.utc,
          payload: payload,
          session_id: session_id,
          trace_id: inbound.trace_id,
          correlation_id: correlation_id || inbound.id,
          causation_id: inbound.id
        )
      end
    end
  end
end
