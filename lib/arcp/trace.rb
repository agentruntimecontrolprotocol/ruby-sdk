# frozen_string_literal: true

require 'arcp/ids'

module Arcp
  # Fiber-local trace context (§17.1).
  #
  # The current `TraceContext` is read from `Fiber[:arcp_trace]` and
  # propagates across fiber suspension/resume boundaries automatically.
  module Tracing
    KEY = :arcp_trace
    private_constant :KEY

    # Immutable per-trace context.
    Context = Data.define(:trace_id, :span_id, :parent_span_id) do
      def child(new_span: SpanId.random)
        Context.new(trace_id: trace_id, span_id: new_span, parent_span_id: span_id)
      end
    end

    # Set the current context for the duration of the block.
    #
    # @param context [Arcp::Tracing::Context]
    # @yield
    def self.with(context)
      previous = Fiber[KEY]
      Fiber[KEY] = context
      yield
    ensure
      Fiber[KEY] = previous
    end

    # @return [Arcp::Tracing::Context, nil]
    def self.current
      Fiber[KEY]
    end

    # @param trace_id [Arcp::TraceId, nil]
    # @return [Arcp::Tracing::Context]
    def self.start(trace_id: nil)
      Context.new(
        trace_id: trace_id || TraceId.random,
        span_id: SpanId.random,
        parent_span_id: nil
      )
    end
  end
end
