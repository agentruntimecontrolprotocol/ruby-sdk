# frozen_string_literal: true

require_relative 'ids'

module Arcp
  module Trace
    KEY = :arcp_trace_context

    Context = Data.define(:trace_id, :span_id, :attributes)

    module_function

    def current
      Fiber[KEY] || Context.new(trace_id: nil, span_id: nil, attributes: {}.freeze)
    end

    def current=(ctx)
      Fiber[KEY] = ctx
    end

    def with(trace_id: nil, span_id: nil, attributes: {})
      prev = current
      Fiber[KEY] = Context.new(
        trace_id: trace_id || prev.trace_id || Arcp::Ids.trace_id,
        span_id: span_id || Arcp::Ids.span_id,
        attributes: prev.attributes.merge(attributes).freeze
      )
      yield current
    ensure
      Fiber[KEY] = prev
    end

    # @return [String] new 32-hex trace id.
    def new_trace_id = Arcp::Ids.trace_id

    def in_span(name, attributes: {}, &)
      tracer = begin
        require 'opentelemetry'
        OpenTelemetry.tracer_provider.tracer('arcp')
      rescue LoadError
        nil
      end

      if tracer
        tracer.in_span(name, attributes: attributes, &)
      else
        with(attributes: attributes, &)
      end
    end
  end
end
