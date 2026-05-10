# frozen_string_literal: true

require 'json'
require 'time'

require 'arcp/envelope'
require 'arcp/error'
require 'arcp/extensions'
require 'arcp/message_type'

module Arcp
  # Envelope encode/decode helpers.
  module Json
    # @param envelope [Envelope]
    # @return [String] JSON
    def self.encode_envelope(envelope)
      JSON.generate(envelope.to_wire_hash)
    end

    # @param string [String] JSON
    # @return [Envelope]
    # @raise [Arcp::Error::ParseError]
    def self.decode_envelope(string)
      raw = JSON.parse(string, symbolize_names: true)
      decode_envelope_hash(raw)
    rescue JSON::ParserError => e
      raise Arcp::Error::ParseError, "invalid JSON: #{e.message}"
    end

    # @param hash [Hash]
    # @return [Envelope]
    def self.decode_envelope_hash(hash)
      raise Arcp::Error::ParseError, 'envelope must be a Hash' unless hash.is_a?(Hash)

      type = require_field(hash, :type)
      raw_payload = hash[:payload] || {}
      payload_class = MessageTypeRegistry.class_for(type)

      Envelope.new(
        arcp: require_field(hash, :arcp),
        id: require_field(hash, :id),
        type: type,
        timestamp: parse_timestamp(require_field(hash, :timestamp)),
        payload: decode_payload(payload_class, type, raw_payload),
        priority: hash[:priority] || Arcp::Priority::NORMAL,
        **envelope_optional_fields(hash)
      )
    rescue ArgumentError => e
      raise Arcp::Error::ParseError, e.message
    end

    def self.envelope_optional_fields(hash)
      {
        source: hash[:source],
        target: hash[:target],
        session_id: hash[:session_id],
        job_id: hash[:job_id],
        stream_id: hash[:stream_id],
        subscription_id: hash[:subscription_id],
        trace_id: hash[:trace_id],
        span_id: hash[:span_id],
        parent_span_id: hash[:parent_span_id],
        correlation_id: hash[:correlation_id],
        causation_id: hash[:causation_id],
        idempotency_key: hash[:idempotency_key],
        extensions: hash[:extensions]
      }
    end

    def self.decode_payload(payload_class, _type, raw_payload)
      return payload_class.from_hash(raw_payload) if payload_class.respond_to?(:from_hash)

      raw_payload
    end

    def self.require_field(hash, name)
      value = hash[name]
      raise Arcp::Error::ParseError, "missing required envelope field: #{name}" if value.nil?

      value
    end

    def self.parse_timestamp(value)
      return value if value.is_a?(Time)

      Time.iso8601(value)
    rescue ArgumentError, TypeError
      raise Arcp::Error::ParseError, "invalid timestamp: #{value.inspect}"
    end

    private_class_method :decode_payload, :require_field, :parse_timestamp,
                         :envelope_optional_fields
  end
end
