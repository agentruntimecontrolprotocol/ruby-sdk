# frozen_string_literal: true

require 'logger'

require 'arcp/capabilities'
require 'arcp/envelope'
require 'arcp/error'
require 'arcp/error_code'
require 'arcp/ids'
require 'arcp/messages/control'
require 'arcp/messages/session'
require 'arcp/version'

module Arcp
  module Client
    # ARCP client. Phase 2 surface: open a session, ping, close.
    class Client
      DEFAULT_CAPABILITIES = {
        streaming: true,
        human_input: true,
        artifacts: true,
        subscriptions: true,
        anonymous: false
      }.freeze

      attr_reader :session_id, :runtime_identity, :capabilities, :logger

      # @param transport [#send_envelope, #receive_envelope, #closed?]
      # @param logger [Logger]
      # @param clock [#now]
      def initialize(transport:, logger: Logger.new(IO::NULL), clock: Time)
        @transport = transport
        @logger = logger
        @clock = clock
      end

      # Open a session. Returns once `session.accepted` arrives.
      #
      # @param auth [Hash] e.g. `{ scheme: 'bearer', token: '...' }`
      # @param client [Hash] client identity block
      # @param capabilities [Hash]
      # @return [Hash] the runtime's capabilities + identity
      # @raise [Arcp::Error::Unauthenticated] on session.rejected
      def open(auth:, client:, capabilities: DEFAULT_CAPABILITIES)
        envelope = build_envelope(
          type: 'session.open',
          payload: Messages::Session::Open.new(
            auth: stringify(auth),
            client: stringify(client),
            capabilities: stringify(capabilities)
          )
        )
        @transport.send_envelope(envelope)

        loop do
          response = @transport.receive_envelope
          raise Arcp::Error::Unavailable, 'transport closed during handshake' if response.nil?

          handled = handle_handshake_response(response)
          return handled if handled
        end
      end

      # Send a ping; wait for the pong; return its received_at.
      #
      # @return [String, nil]
      def ping
        envelope = build_envelope(
          type: 'ping',
          payload: Messages::Control::Ping.new(sent_at: @clock.now.utc.iso8601(6)),
          session_id: @session_id
        )
        @transport.send_envelope(envelope)
        response = @transport.receive_envelope
        raise Arcp::Error::Unavailable, 'transport closed waiting for pong' if response.nil?

        case response.payload
        in Messages::Control::Pong => pong then pong.received_at
        in Messages::Control::Nack => nack then raise Arcp::Error::Internal, nack.message
        else raise Arcp::Error::Internal, "unexpected ping response: #{response.type}"
        end
      end

      def close
        return if @transport.closed?

        envelope = build_envelope(
          type: 'session.close',
          payload: Messages::Session::Close.new(reason: 'client_close', detach: false),
          session_id: @session_id
        )
        @transport.send_envelope(envelope)
        @transport.close
      end

      private

      def handle_handshake_response(envelope)
        case envelope.payload
        in Messages::Session::Accepted => accepted
          @session_id = SessionId.new(value: accepted.session_id)
          @runtime_identity = accepted.runtime
          @capabilities = Capabilities.normalize(accepted.capabilities)
          { session_id: @session_id, runtime: accepted.runtime, capabilities: @capabilities }
        in Messages::Session::Rejected => rejected
          raise rejection_error(rejected)
        in Messages::Session::Challenge
          raise Arcp::Error::Unimplemented.new(
            section: '§8.1',
            detail: 'session.challenge response not implemented in v0.1'
          )
        else
          nil
        end
      end

      def rejection_error(rejected)
        case rejected.code
        when ErrorCode::UNAUTHENTICATED then Arcp::Error::Unauthenticated.new(rejected.message)
        when ErrorCode::UNIMPLEMENTED   then Arcp::Error::Unimplemented.new(section: '§8',
                                                                            detail: rejected.message)
        else Arcp::Error::Internal.new(rejected.message)
        end
      end

      def build_envelope(type:, payload:, session_id: nil)
        Envelope.new(
          arcp: Arcp::PROTOCOL_VERSION,
          id: MessageId.random,
          type: type,
          timestamp: @clock.now.utc,
          payload: payload,
          session_id: session_id
        )
      end

      def stringify(hash)
        return {} if hash.nil?

        hash.each_with_object({}) do |(k, v), acc|
          acc[k.to_s] = v.is_a?(Hash) ? stringify(v) : v
        end
      end
    end
  end
end
