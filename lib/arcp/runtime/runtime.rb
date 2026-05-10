# frozen_string_literal: true

require 'logger'
require 'async'

require 'arcp/auth/auth_scheme'
require 'arcp/capabilities'
require 'arcp/envelope'
require 'arcp/error'
require 'arcp/error_code'
require 'arcp/ids'
require 'arcp/runtime/job_manager'
require 'arcp/runtime/lease_manager'
require 'arcp/runtime/pending_registry'
require 'arcp/runtime/session'
require 'arcp/runtime/session_helper'
require 'arcp/runtime/stream_manager'
require 'arcp/store/event_log'
require 'arcp/version'

module Arcp
  module Runtime
    # Per-session runtime state. Created on a successful handshake.
    class SessionContext
      attr_accessor :helper, :parent_task
      attr_reader :record, :transport, :job_manager, :stream_manager, :pending, :lease_manager

      def initialize(record:, transport:, job_manager:, stream_manager:, pending:,
                     lease_manager:, helper: nil)
        @record = record
        @transport = transport
        @job_manager = job_manager
        @stream_manager = stream_manager
        @pending = pending
        @lease_manager = lease_manager
        @helper = helper
      end

      def session_id = record.session_id
    end

    # ARCP runtime. Accepts client connections, drives session
    # handshakes, and dispatches authenticated traffic to per-session
    # job, stream, subscription, and artifact managers.
    #
    # Tools are registered with `register_tool('name') { |ctx, args| ... }`.
    # The block is run inside the job's child task; the return value
    # becomes the `tool.result.value`. Raising any `Arcp::Error`
    # subclass terminates the job with the corresponding code.
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

      attr_reader :event_log, :logger, :capabilities, :identity, :tools

      def initialize(schemes: [], identity: DEFAULT_RUNTIME_IDENTITY,
                     capabilities: DEFAULT_CAPABILITIES, event_log: nil,
                     logger: Logger.new(IO::NULL), clock: Time)
        @schemes = schemes.to_h { |s| [s.scheme_name, s] }.freeze
        @identity = identity.freeze
        @capabilities = capabilities.freeze
        @event_log = event_log || Store::EventLog.new
        @logger = logger
        @clock = clock
        @tools = {}
        @sessions = {}
        @sessions_mutex = Mutex.new
      end

      # Register a tool that can be invoked via `tool.invoke`.
      #
      # @param name [String]
      # @yield [ctx, arguments]
      def register_tool(name, &block)
        raise ArgumentError, 'block required' unless block

        @tools[name] = block
      end

      # @api private
      # Emit a fully-formed envelope through the session's transport
      # and persist it to the event log. Used by SessionHelper.
      def emit_session_envelope(ctx, envelope)
        @event_log.append(envelope)
        ctx.transport.send_envelope(envelope)
      end

      def serve(transport)
        session_id = SessionId.random
        record = handshake(transport, session_id)
        return unless record

        Async do |task|
          session_ctx = build_session_context(record, transport, task)
          @sessions_mutex.synchronize { @sessions[session_id.value] = session_ctx }
          dispatch_loop(session_ctx)
        ensure
          @sessions_mutex.synchronize { @sessions.delete(session_id.value) }
        end.wait
      end

      private

      def handshake(transport, session_id)
        negotiator = SessionNegotiator.new(
          session_id: session_id,
          runtime_identity: @identity,
          runtime_capabilities: @capabilities,
          schemes: @schemes
        )
        loop do
          envelope = transport.receive_envelope
          return nil if envelope.nil?

          @event_log.append(envelope)
          result = negotiator.receive(envelope)
          (result[:outbound] || []).each do |payload|
            send_outbound(transport, envelope, payload, session_id, correlation_id: envelope.id)
          end
          return result[:record] if result[:record]
          return nil if negotiator.state == :closed
        end
      end

      def build_session_context(record, transport, parent_task)
        emit = lambda do |source_record, payload|
          emit_session_message(transport, record, source_record, payload)
        end
        ctx = SessionContext.new(
          record: record,
          transport: transport,
          job_manager: JobManager.new(
            clock: @clock,
            heartbeat_interval_seconds: record.capabilities[:heartbeat_interval_seconds],
            heartbeat_recovery: record.capabilities[:heartbeat_recovery],
            emit: emit
          ),
          stream_manager: StreamManager.new(emit: emit),
          pending: PendingRegistry.new,
          lease_manager: LeaseManager.new(emit: emit, clock: @clock)
        )
        ctx.parent_task = parent_task
        ctx.helper = SessionHelper.new(runtime: self, ctx: ctx)
        ctx
      end

      def dispatch_loop(ctx)
        loop do
          envelope = ctx.transport.receive_envelope
          break if envelope.nil?

          @event_log.append(envelope)
          dispatch(envelope, ctx)
        end
      end

      def dispatch(envelope, ctx)
        case envelope.payload
        in Messages::Session::Close
          handle_session_close(ctx)
        in Messages::Control::Ping
          send_pong(envelope, ctx)
        in Messages::Execution::ToolInvoke => invoke
          handle_tool_invoke(envelope, invoke, ctx)
        in Messages::Control::Cancel => cancel
          handle_cancel(envelope, cancel, ctx)
        in Messages::Control::Interrupt => interrupt
          handle_interrupt(envelope, interrupt, ctx)
        in Messages::Human::InputResponse => response
          ctx.pending.resolve(envelope.correlation_id&.value, response)
          ctx.job_manager.unblock(envelope.job_id) if envelope.job_id
        in Messages::Human::ChoiceResponse => response
          ctx.pending.resolve(envelope.correlation_id&.value, response)
          ctx.job_manager.unblock(envelope.job_id) if envelope.job_id
        in Messages::Permissions::PermissionGrant | Messages::Permissions::PermissionDeny
          ctx.pending.resolve(envelope.correlation_id&.value, envelope.payload)
        else
          send_unimplemented(envelope, ctx)
        end
      end

      def handle_session_close(ctx)
        @logger.info('arcp.runtime') { "session closed: #{ctx.session_id.value}" }
        ctx.transport.close
      end

      def send_pong(envelope, ctx)
        pong = Messages::Control::Pong.new(received_at: @clock.now.utc.iso8601(6))
        send_outbound(ctx.transport, envelope, pong, ctx.session_id, correlation_id: envelope.id)
      end

      def handle_tool_invoke(envelope, invoke, ctx)
        tool = @tools[invoke.tool]
        if tool.nil?
          send_tool_error(envelope, ctx, code: ErrorCode::NOT_FOUND, message: "no tool: #{invoke.tool}")
          return
        end

        job_id = ctx.job_manager.accept(
          session_id: ctx.session_id, tool: invoke.tool, arguments: invoke.arguments,
          correlation_id: envelope.id, trace_id: envelope.trace_id
        )
        parent = ctx.parent_task
        extras = {
          streams: ctx.stream_manager,
          pending: ctx.pending,
          helper: ctx.helper,
          leases: ctx.lease_manager
        }
        ctx.job_manager.start(parent, job_id, extras: extras) do |jctx|
          tool.call(jctx, invoke.arguments)
        end
      end

      def handle_cancel(envelope, cancel, ctx)
        if cancel.target == 'job'
          accepted = ctx.job_manager.cancel!(JobId.new(value: cancel.target_id),
                                             reason: cancel.reason,
                                             deadline_ms: cancel.deadline_ms || 5_000)
          unless accepted
            refused = Messages::Control::CancelRefused.new(
              target: cancel.target, target_id: cancel.target_id,
              reason: 'not_cancellable_or_already_terminal'
            )
            send_outbound(ctx.transport, envelope, refused, ctx.session_id, correlation_id: envelope.id)
          end
        else
          send_unimplemented(envelope, ctx)
        end
      end

      def handle_interrupt(envelope, interrupt, ctx)
        if interrupt.target == 'job'
          job_id = JobId.new(value: interrupt.target_id)
          ctx.job_manager.block(job_id)
          input = Messages::Human::InputRequest.new(
            prompt: interrupt.prompt || 'job interrupted; awaiting human guidance',
            response_schema: nil, default: nil,
            expires_at: nil, destinations: nil
          )
          send_outbound(ctx.transport, envelope, input, ctx.session_id, job_id: job_id,
                                                                        correlation_id: envelope.id)
        else
          send_unimplemented(envelope, ctx)
        end
      end

      def send_tool_error(envelope, ctx, code:, message:)
        payload = Messages::Execution::ToolError.new(
          code: code, message: message, retryable: false,
          details: nil, cause: nil, trace_id: envelope.trace_id&.value
        )
        send_outbound(ctx.transport, envelope, payload, ctx.session_id, correlation_id: envelope.id)
      end

      def send_unimplemented(envelope, ctx)
        nack = Messages::Control::Nack.new(
          code: ErrorCode::UNIMPLEMENTED,
          message: "type not implemented in v0.1: #{envelope.type}",
          details: { type: envelope.type }, retryable: false
        )
        send_outbound(ctx.transport, envelope, nack, ctx.session_id, correlation_id: envelope.id)
      end

      def send_outbound(transport, inbound, payload, session_id, correlation_id: nil, job_id: nil,
                        stream_id: nil)
        envelope = Envelope.new(
          arcp: Arcp::PROTOCOL_VERSION,
          id: MessageId.random,
          type: payload.class.type_name,
          timestamp: @clock.now.utc,
          payload: payload,
          session_id: session_id,
          job_id: job_id,
          stream_id: stream_id,
          trace_id: inbound&.trace_id,
          correlation_id: correlation_id || inbound&.id,
          causation_id: inbound&.id
        )
        @event_log.append(envelope)
        transport.send_envelope(envelope)
      end

      def emit_session_message(transport, session_record, source_record, payload)
        job_id = source_record.respond_to?(:job_id) ? source_record.job_id : nil
        stream_id = source_record.respond_to?(:stream_id) ? source_record.stream_id : nil
        correlation_id = source_record.respond_to?(:correlation_id) ? source_record.correlation_id : nil
        trace_id = source_record.respond_to?(:trace_id) ? source_record.trace_id : nil
        envelope = Envelope.new(
          arcp: Arcp::PROTOCOL_VERSION,
          id: MessageId.random,
          type: payload.class.type_name,
          timestamp: @clock.now.utc,
          payload: payload,
          session_id: session_record.session_id,
          job_id: job_id,
          stream_id: stream_id,
          trace_id: trace_id,
          correlation_id: correlation_id
        )
        @event_log.append(envelope)
        transport.send_envelope(envelope)
      end
    end
  end
end
