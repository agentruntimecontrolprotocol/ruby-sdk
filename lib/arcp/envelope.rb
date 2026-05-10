# frozen_string_literal: true

require 'time'

require 'arcp/error'
require 'arcp/ids'
require 'arcp/priority'
require 'arcp/version'

module Arcp
  # Canonical ARCP message envelope (§6.1).
  #
  # Constructed via `Arcp::Envelope.new(...)` with all required fields.
  # Optional fields default to `nil`. Pattern-matchable via the included
  # `Data` semantics: `case env in Envelope(payload: SomeMessage::Payload)`.
  Envelope = Data.define(
    :arcp,
    :id,
    :type,
    :timestamp,
    :payload,
    :source,
    :target,
    :session_id,
    :job_id,
    :stream_id,
    :subscription_id,
    :trace_id,
    :span_id,
    :parent_span_id,
    :correlation_id,
    :causation_id,
    :idempotency_key,
    :priority,
    :extensions
  ) do
    # @param arcp [String] protocol version, e.g. "1.0"
    # @param id [Arcp::MessageId, String]
    # @param type [String] wire type
    # @param timestamp [Time]
    # @param payload [Object] payload Data instance (or Hash for unknown types)
    # @param priority [String] one of Arcp::Priority::ALL
    # @return [Envelope]
    def initialize(arcp:, id:, type:, timestamp:, payload:, source: nil, target: nil,
                   session_id: nil, job_id: nil, stream_id: nil, subscription_id: nil,
                   trace_id: nil, span_id: nil, parent_span_id: nil,
                   correlation_id: nil, causation_id: nil, idempotency_key: nil,
                   priority: Arcp::Priority::NORMAL, extensions: nil)
      raise ArgumentError, 'arcp must be a String' unless arcp.is_a?(String)
      raise ArgumentError, 'type must be a String' unless type.is_a?(String) && !type.empty?
      raise ArgumentError, 'timestamp must be a Time' unless timestamp.is_a?(Time)
      unless Arcp::Priority.valid?(priority)
        raise ArgumentError, "priority must be one of #{Arcp::Priority::ALL.inspect}, got #{priority.inspect}"
      end

      id = MessageId.new(value: id) if id.is_a?(String)
      raise ArgumentError, 'id must be a MessageId' unless id.is_a?(MessageId)

      session_id      = SessionId.new(value: session_id) if session_id.is_a?(String)
      job_id          = JobId.new(value: job_id) if job_id.is_a?(String)
      stream_id       = StreamId.new(value: stream_id) if stream_id.is_a?(String)
      subscription_id = SubscriptionId.new(value: subscription_id) if subscription_id.is_a?(String)
      trace_id        = TraceId.new(value: trace_id) if trace_id.is_a?(String)
      span_id         = SpanId.new(value: span_id) if span_id.is_a?(String)
      parent_span_id  = SpanId.new(value: parent_span_id) if parent_span_id.is_a?(String)
      correlation_id  = MessageId.new(value: correlation_id) if correlation_id.is_a?(String)
      causation_id    = MessageId.new(value: causation_id) if causation_id.is_a?(String)

      super
    end

    # Convenience constructor that fills in defaults for the boilerplate
    # fields. Useful in samples and tests.
    #
    # @param type [String]
    # @param payload [Object]
    # @return [Envelope]
    def self.build(type:, payload:, **kwargs)
      new(
        arcp: Arcp::PROTOCOL_VERSION,
        id: kwargs.delete(:id) || MessageId.random,
        type: type,
        timestamp: kwargs.delete(:timestamp) || Time.now.utc,
        payload: payload,
        **kwargs
      )
    end

    # Marshal to a wire-shaped Hash. Excludes nil-valued keys so the
    # JSON body contains only the fields actually set.
    #
    # @return [Hash]
    def to_wire_hash
      core_hash.merge(id_hash).merge(metadata_hash).compact
    end

    private

    def core_hash
      {
        arcp: arcp,
        id: id.value,
        type: type,
        timestamp: timestamp.utc.iso8601(6),
        payload: payload_to_wire
      }
    end

    def id_hash
      {
        session_id: session_id&.value,
        job_id: job_id&.value,
        stream_id: stream_id&.value,
        subscription_id: subscription_id&.value,
        trace_id: trace_id&.value,
        span_id: span_id&.value,
        parent_span_id: parent_span_id&.value,
        correlation_id: correlation_id&.value,
        causation_id: causation_id&.value
      }
    end

    def metadata_hash
      {
        source: source,
        target: target,
        idempotency_key: idempotency_key,
        priority: priority == Arcp::Priority::NORMAL ? nil : priority,
        extensions: extensions
      }
    end

    def payload_to_wire
      return payload if payload.is_a?(Hash)
      return payload.to_h if payload.respond_to?(:to_h)

      raise Arcp::Error::Internal, "payload of type #{payload.class} is not serializable"
    end
  end
end
