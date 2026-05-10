# frozen_string_literal: true

require 'arcp/error'
require 'arcp/message_type'

module Arcp
  module Messages
    # Define and register a payload class.
    #
    # Returns a `Data.define(...)` class registered against the given
    # wire-type name. The class exposes `type_name`, `required_keys`,
    # `optional_keys`, and `from_hash` factory.
    #
    # @param wire_name [String] e.g. "session.open"
    # @param required [Array<Symbol>] required keys (raise on absence)
    # @param optional [Hash{Symbol=>Object}] optional keys keyed to defaults
    # @return [Class]
    def self.define(wire_name, required: [], optional: {})
      all_keys = (required + optional.keys).uniq
      payload_class = Data.define(*all_keys)

      payload_class.define_singleton_method(:type_name) { wire_name }
      payload_class.define_singleton_method(:required_keys) { required.dup }
      payload_class.define_singleton_method(:optional_keys) { optional.keys.dup }
      payload_class.define_singleton_method(:from_hash) do |hash|
        Arcp::Messages.build_payload(self, wire_name, required, optional, hash)
      end

      MessageTypeRegistry.register(wire_name, payload_class)
      payload_class
    end

    # @api private
    def self.build_payload(payload_class, wire_name, required, optional, hash)
      sym = symbolize(hash)
      required.each do |key|
        raise Arcp::Error::ParseError, "missing required field for #{wire_name}: #{key}" unless sym.key?(key)
      end
      kwargs = {}
      required.each { |k| kwargs[k] = sym[k] }
      optional.each { |k, default| kwargs[k] = sym.fetch(k, default) }
      payload_class.new(**kwargs)
    end

    # @api private
    def self.symbolize(hash)
      return {} unless hash.is_a?(Hash)
      return hash if hash.keys.first.is_a?(Symbol) || hash.empty?

      hash.transform_keys(&:to_sym)
    end
  end
end
