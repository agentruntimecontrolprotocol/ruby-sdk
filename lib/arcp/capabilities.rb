# frozen_string_literal: true

module Arcp
  # Capability negotiation (§7).
  #
  # Capabilities are a Hash of symbol keys to values. Boolean keys
  # default to `false` if absent. Specific values default per the RFC
  # when otherwise unspecified.
  module Capabilities
    BOOLEAN_KEYS = %i[
      streaming durable_jobs checkpoints binary_streams
      agent_handoff human_input artifacts subscriptions scheduled_jobs
      anonymous interrupt
    ].freeze

    DEFAULT_HEARTBEAT_INTERVAL_SECONDS = 30
    DEFAULT_HEARTBEAT_RECOVERY = 'fail'

    # Normalize an inbound capabilities hash from the wire.
    #
    # Accepts string- or symbol-keyed hashes and returns a frozen
    # symbol-keyed hash with defaults applied.
    #
    # @param hash [Hash, nil]
    # @return [Hash{Symbol=>Object}]
    def self.normalize(hash)
      sym = symbolize(hash)
      result = {}
      BOOLEAN_KEYS.each { |k| result[k] = sym.fetch(k, false) ? true : false }
      result[:heartbeat_interval_seconds] =
        sym.fetch(:heartbeat_interval_seconds, DEFAULT_HEARTBEAT_INTERVAL_SECONDS)
      result[:heartbeat_recovery]         = sym.fetch(:heartbeat_recovery, DEFAULT_HEARTBEAT_RECOVERY)
      result[:binary_encoding]            = sym.fetch(:binary_encoding, ['base64'])
      result[:extensions]                 = Array(sym.fetch(:extensions, [])).freeze
      result.freeze
    end

    # Negotiate two capability sets: take logical AND of booleans, the
    # smaller of `heartbeat_interval_seconds`, and the intersection of
    # `extensions`. The grantor's `heartbeat_recovery` wins.
    #
    # @param client_caps [Hash]
    # @param runtime_caps [Hash]
    # @return [Hash{Symbol=>Object}]
    def self.negotiate(client_caps, runtime_caps)
      a = normalize(client_caps)
      b = normalize(runtime_caps)
      negotiated = {}
      BOOLEAN_KEYS.each { |k| negotiated[k] = a[k] && b[k] }
      negotiated[:heartbeat_interval_seconds] =
        [a[:heartbeat_interval_seconds], b[:heartbeat_interval_seconds]].min
      negotiated[:heartbeat_recovery] = b[:heartbeat_recovery]
      shared_encoding = a[:binary_encoding] & b[:binary_encoding]
      negotiated[:binary_encoding] = shared_encoding.empty? ? ['base64'] : shared_encoding
      negotiated[:extensions] = (a[:extensions] & b[:extensions]).freeze
      negotiated.freeze
    end

    def self.symbolize(hash)
      return {} if hash.nil?
      raise ArgumentError, 'capabilities must be a Hash' unless hash.is_a?(Hash)
      return hash if hash.empty? || hash.keys.first.is_a?(Symbol)

      hash.transform_keys(&:to_sym)
    end
    private_class_method :symbolize
  end
end
