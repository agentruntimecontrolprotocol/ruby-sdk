# frozen_string_literal: true

# OTLP exporter for `metric` and `trace.span` envelopes (RFC §17).
class OTLPSink
  def initialize(endpoint:)
    @endpoint = endpoint
    # Real version: opentelemetry-exporter-otlp gem; meter/tracer providers.
  end

  def handle(event)
    case event['type']
    when 'metric'
      # Standard names (§17.3.1): tokens.used, cost.usd, latency.ms
      # map directly to OTLP counters / histograms.
      raise NotImplementedError
    when 'trace.span'
      # `trace.span` mirrors OpenTelemetry's span shape; emit via tracer.
      raise NotImplementedError, 'trace.span -> OTLP span not implemented'
    end
  end
end
