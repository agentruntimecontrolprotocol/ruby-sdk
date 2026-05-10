# frozen_string_literal: true

require 'arcp/messages/base'

module Arcp
  module Messages
    # Observability payloads (§17).
    module Telemetry
      LEVEL_TRACE    = 'trace'
      LEVEL_DEBUG    = 'debug'
      LEVEL_INFO     = 'info'
      LEVEL_WARN     = 'warn'
      LEVEL_ERROR    = 'error'
      LEVEL_CRITICAL = 'critical'

      LEVELS = [LEVEL_TRACE, LEVEL_DEBUG, LEVEL_INFO, LEVEL_WARN, LEVEL_ERROR, LEVEL_CRITICAL].freeze

      EventEmit = Arcp::Messages.define('event.emit',
                                        required: %i[name],
                                        optional: { value: nil, attributes: {} })
      Log       = Arcp::Messages.define('log',
                                        required: %i[level message],
                                        optional: { attributes: {} })
      Metric    = Arcp::Messages.define('metric',
                                        required: %i[name value],
                                        optional: { unit: nil, dims: {} })
      TraceSpan = Arcp::Messages.define('trace.span',
                                        required: %i[trace_id span_id name],
                                        optional: {
                                          parent_span_id: nil,
                                          start_time: nil,
                                          end_time: nil,
                                          attributes: {},
                                          status: 'ok'
                                        })

      # Standard metric names (§17.3.1).
      module StandardMetrics
        TOKENS_USED       = 'tokens.used'
        COST_USD          = 'cost.usd'
        GPU_SECONDS       = 'gpu.seconds'
        TOOL_INVOCATIONS  = 'tool.invocations'
        LATENCY_MS        = 'latency.ms'
        BYTES_IN          = 'bytes.in'
        BYTES_OUT         = 'bytes.out'
        ERRORS_TOTAL      = 'errors.total'

        ALL = [
          TOKENS_USED, COST_USD, GPU_SECONDS, TOOL_INVOCATIONS,
          LATENCY_MS, BYTES_IN, BYTES_OUT, ERRORS_TOTAL
        ].freeze
      end
    end
  end
end
