# frozen_string_literal: true

require_relative 'version'
require_relative 'ids'
require_relative 'errors'
require_relative 'serializer'
require_relative 'message_types'

module Arcp
  # ARCP wire envelope per spec §5.1. Eight fields:
  # arcp, id, type, session_id, trace_id, job_id, event_seq, payload.
  #
  # `trace_id` and `job_id` may be nil for session-level envelopes.
  # `event_seq` is nil for non-event traffic; events carry a monotonic Integer.
  Envelope = Data.define(:arcp, :id, :type, :session_id, :trace_id, :job_id, :event_seq, :payload) do
    HEX32 = /\A[0-9a-f]{32}\z/

    def self.build(type:, session_id:, payload:, trace_id: nil, job_id: nil, event_seq: nil, id: nil)
      raise Arcp::Errors::InvalidRequest, 'trace_id must be 32 hex chars' if trace_id && trace_id !~ HEX32

      new(
        arcp: Arcp::PROTOCOL_VERSION,
        id: id || Arcp::Ids.envelope_id,
        type: type,
        session_id: session_id,
        trace_id: trace_id,
        job_id: job_id,
        event_seq: event_seq,
        payload: payload || {}
      )
    end

    def self.from_h(hash)
      raise Arcp::Errors::InvalidRequest, 'envelope must be a Hash' unless hash.is_a?(Hash)

      h = hash.transform_keys(&:to_s)
      arcp = h['arcp']
      unless arcp == Arcp::PROTOCOL_VERSION
        raise Arcp::Errors::InvalidRequest, "unsupported arcp version: #{arcp.inspect}"
      end

      type = h['type']
      raise Arcp::Errors::InvalidRequest, 'envelope type must be a String' unless type.is_a?(String)

      session_id = h['session_id']
      unless session_id.is_a?(String)
        raise Arcp::Errors::InvalidRequest,
              'envelope session_id must be a String'
      end

      event_seq = h['event_seq']
      unless event_seq.nil? || event_seq.is_a?(Integer)
        raise Arcp::Errors::InvalidRequest,
              'event_seq must be an Integer'
      end

      trace_id = h['trace_id']
      raise Arcp::Errors::InvalidRequest, 'trace_id must be 32 hex chars' if trace_id && trace_id !~ HEX32

      payload = h['payload']
      raise Arcp::Errors::InvalidRequest, 'payload must be a Hash' unless payload.is_a?(Hash) || payload.nil?

      new(
        arcp: arcp,
        id: h.fetch('id'),
        type: type,
        session_id: session_id,
        trace_id: trace_id,
        job_id: h['job_id'],
        event_seq: event_seq,
        payload: deep_freeze(payload || {})
      )
    end

    def self.from_json(bytes)
      from_h(Arcp::Serializer.load(bytes))
    end

    # @api private
    def self.deep_freeze(value)
      case value
      when Hash
        value.each_value { |v| deep_freeze(v) }
      when Array
        value.each { |v| deep_freeze(v) }
      end
      value.freeze
    end

    def to_h
      h = { 'arcp' => arcp, 'id' => id, 'type' => type, 'session_id' => session_id,
            'payload' => stringify(payload) }
      h['trace_id']  = trace_id  if trace_id
      h['job_id']    = job_id    if job_id
      h['event_seq'] = event_seq if event_seq
      h
    end

    def to_json(*_args) = Arcp::Serializer.dump(to_h)

    # @api private
    def stringify(value)
      case value
      when Hash  then value.transform_keys(&:to_s).transform_values { |v| stringify(v) }
      when Array then value.map { |v| stringify(v) }
      else value
      end
    end

    def known? = Arcp::MessageTypes.known?(type)
  end

  # @api private
  UnknownEnvelope = Data.define(:envelope) do
    def type = envelope.type
    def payload = envelope.payload
  end
end
