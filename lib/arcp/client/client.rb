# frozen_string_literal: true

require 'logger'
require 'async'

require 'arcp/capabilities'
require 'arcp/envelope'
require 'arcp/error'
require 'arcp/error_code'
require 'arcp/ids'
require 'arcp/messages/control'
require 'arcp/messages/execution'
require 'arcp/messages/human'
require 'arcp/messages/permissions'
require 'arcp/messages/session'
require 'arcp/version'

module Arcp
  module Client
    # ARCP client.
    #
    # Phase 3 surface: handshake, ping, tool.invoke with streaming
    # progress, cancel, interrupt.
    class Client
      DEFAULT_CAPABILITIES = {
        streaming: true,
        human_input: true,
        artifacts: true,
        subscriptions: true,
        anonymous: false
      }.freeze

      # Result of a `tool.invoke`. `events` lists every event observed
      # (including job/stream messages); `terminal` is the terminal event.
      InvocationResult = Data.define(:job_id, :events, :terminal) do
        def value
          case terminal&.payload
          in Arcp::Messages::Execution::ToolResult => r then r.value
          in Arcp::Messages::Execution::JobCompleted => c then c.value
          else nil
          end
        end

        def successful?
          terminal&.payload.is_a?(Arcp::Messages::Execution::ToolResult) ||
            terminal&.payload.is_a?(Arcp::Messages::Execution::JobCompleted)
        end
      end

      attr_reader :session_id, :runtime_identity, :capabilities, :logger

      def initialize(transport:, logger: Logger.new(IO::NULL), clock: Time)
        @transport = transport
        @logger = logger
        @clock = clock
        @input_handler = nil
        @permission_handler = nil
      end

      # Open a session.
      def open(auth:, client:, capabilities: DEFAULT_CAPABILITIES)
        envelope = build_envelope(
          type: 'session.open',
          payload: Messages::Session::Open.new(
            auth: stringify(auth), client: stringify(client), capabilities: stringify(capabilities)
          )
        )
        @transport.send_envelope(envelope)

        loop do
          response = receive_or_raise
          handled = handle_handshake_response(response)
          return handled if handled
        end
      end

      # Send a ping.
      def ping
        send_envelope(type: 'ping', payload: Messages::Control::Ping.new(sent_at: @clock.now.utc.iso8601(6)))
        response = receive_or_raise
        case response.payload
        in Messages::Control::Pong => pong then pong.received_at
        in Messages::Control::Nack => nack then raise Arcp::Error::Internal, nack.message
        else raise Arcp::Error::Internal, "unexpected ping response: #{response.type}"
        end
      end

      # Provide an input handler that responds to `human.input.request`.
      # The handler receives the request envelope and returns a value
      # matching the request's `response_schema`, or `:default` to use
      # the request's default, or `:cancel` to cancel.
      def on_human_input(&block)
        @input_handler = block
      end

      def on_permission_request(&block)
        @permission_handler = block
      end

      # Invoke a tool synchronously, returning an InvocationResult.
      #
      # Streams progress, heartbeat, and stream events into `events`.
      # Optionally yields each envelope as it arrives.
      #
      # @param tool [String]
      # @param arguments [Hash]
      # @yieldparam envelope [Arcp::Envelope]
      def invoke(tool:, arguments: {}, &block)
        invoke_envelope = build_envelope(
          type: 'tool.invoke',
          payload: Messages::Execution::ToolInvoke.new(tool: tool, arguments: arguments),
          session_id: @session_id
        )
        @transport.send_envelope(invoke_envelope)

        events = []
        terminal = nil
        job_id = nil
        loop do
          envelope = receive_or_raise
          events << envelope
          block&.call(envelope)
          maybe_handle_request(envelope)
          job_id ||= envelope.job_id if envelope.payload.is_a?(Messages::Execution::JobAccepted) ||
                                        envelope.payload.is_a?(Messages::Execution::JobStarted)
          if terminal_event?(envelope.payload)
            terminal = envelope
            break
          end
        end
        InvocationResult.new(job_id: job_id, events: events, terminal: terminal)
      end

      # Cancel a job by id.
      def cancel(job_id, reason: 'user_aborted', deadline_ms: 5_000)
        send_envelope(
          type: 'cancel',
          payload: Messages::Control::Cancel.new(
            target: 'job', target_id: job_id_value(job_id),
            reason: reason, deadline_ms: deadline_ms
          ),
          job_id: job_id
        )
      end

      # Interrupt a job (request human-driven pause).
      def interrupt(job_id, prompt: nil)
        send_envelope(
          type: 'interrupt',
          payload: Messages::Control::Interrupt.new(
            target: 'job', target_id: job_id_value(job_id), prompt: prompt
          ),
          job_id: job_id
        )
      end

      def close
        return if @transport.closed?

        send_envelope(
          type: 'session.close',
          payload: Messages::Session::Close.new(reason: 'client_close', detach: false)
        )
        @transport.close
      end

      private

      def maybe_handle_request(envelope)
        case envelope.payload
        in Messages::Human::InputRequest => req
          dispatch_human_input(envelope, req)
        in Messages::Permissions::PermissionRequest => req
          dispatch_permission(envelope, req)
        else
          # nothing
        end
      end

      def dispatch_human_input(envelope, req)
        return unless @input_handler

        value = @input_handler.call(envelope)
        if value == :cancel
          # caller is responsible for sending a cancel separately
          return
        end

        actual = value == :default ? req.default : value
        response = Messages::Human::InputResponse.new(
          value: actual,
          responded_by: 'client',
          responded_at: @clock.now.utc.iso8601(6)
        )
        send_envelope(
          type: 'human.input.response',
          payload: response,
          job_id: envelope.job_id,
          correlation_id: envelope.id
        )
      end

      def dispatch_permission(envelope, req)
        return unless @permission_handler

        decision = @permission_handler.call(envelope)
        payload =
          if decision == :grant
            Messages::Permissions::PermissionGrant.new(
              permission: req.permission, resource: req.resource, operation: req.operation,
              lease_seconds: req.requested_lease_seconds, attestation: nil
            )
          else
            Messages::Permissions::PermissionDeny.new(
              permission: req.permission, resource: req.resource, operation: req.operation,
              reason: decision.is_a?(Hash) ? decision[:reason] : 'denied'
            )
          end
        send_envelope(
          type: payload.class.type_name, payload: payload,
          job_id: envelope.job_id, correlation_id: envelope.id
        )
      end

      def terminal_event?(payload)
        payload.is_a?(Messages::Execution::ToolResult) ||
          payload.is_a?(Messages::Execution::ToolError) ||
          payload.is_a?(Messages::Execution::JobCompleted) ||
          payload.is_a?(Messages::Execution::JobFailed) ||
          payload.is_a?(Messages::Execution::JobCancelled) ||
          payload.is_a?(Messages::Control::Nack)
      end

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
          raise Arcp::Error::Unimplemented.new(section: '§8.1',
                                               detail: 'challenge response not implemented in v0.1')
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

      def send_envelope(type:, payload:, job_id: nil, stream_id: nil, correlation_id: nil)
        envelope = build_envelope(
          type: type, payload: payload, session_id: @session_id,
          job_id: job_id, stream_id: stream_id, correlation_id: correlation_id
        )
        @transport.send_envelope(envelope)
      end

      def build_envelope(type:, payload:, session_id: nil, job_id: nil, stream_id: nil, correlation_id: nil)
        Envelope.new(
          arcp: Arcp::PROTOCOL_VERSION,
          id: MessageId.random,
          type: type,
          timestamp: @clock.now.utc,
          payload: payload,
          session_id: session_id,
          job_id: job_id,
          stream_id: stream_id,
          correlation_id: correlation_id
        )
      end

      def receive_or_raise
        response = @transport.receive_envelope
        raise Arcp::Error::Unavailable, 'transport closed unexpectedly' if response.nil?

        response
      end

      def stringify(hash)
        return {} if hash.nil?

        hash.each_with_object({}) { |(k, v), acc| acc[k.to_s] = v.is_a?(Hash) ? stringify(v) : v }
      end

      def job_id_value(job_id)
        job_id.respond_to?(:value) ? job_id.value : job_id
      end
    end
  end
end
