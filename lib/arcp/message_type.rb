# frozen_string_literal: true

require 'arcp/error'

module Arcp
  # Registry of known ARCP message types.
  #
  # Each message type registers a payload class. The payload class is a
  # `Data.define(...)` exposing `from_hash` and `to_h`. The wire `type`
  # field is mapped to the registered class on receive.
  module MessageTypeRegistry
    @types = {}
    @mutex = Mutex.new

    class << self
      # Register a payload class for a wire type name.
      #
      # @param wire_name [String] e.g. "session.open"
      # @param payload_class [Class]
      # @raise [ArgumentError] if already registered
      def register(wire_name, payload_class)
        @mutex.synchronize do
          if @types.key?(wire_name) && @types[wire_name] != payload_class
            raise ArgumentError, "duplicate registration for #{wire_name.inspect}"
          end

          @types[wire_name] = payload_class
        end
      end

      # @param wire_name [String]
      # @return [Class, nil]
      def class_for(wire_name)
        @mutex.synchronize { @types[wire_name] }
      end

      # @param payload_class [Class]
      # @return [String, nil]
      def name_for(payload_class)
        @mutex.synchronize do
          @types.each { |name, klass| return name if klass == payload_class }
          nil
        end
      end

      # @return [Array<String>]
      def known
        @mutex.synchronize { @types.keys.dup }
      end

      # Whether a wire-type name is part of the core protocol surface
      # (i.e. not namespaced as an extension per §21.1).
      #
      # @param wire_name [String]
      # @return [Boolean]
      def core?(wire_name)
        return false if wire_name.nil? || wire_name.empty?
        return false if Extensions.namespaced?(wire_name)
        return false if wire_name.start_with?('x-')

        true
      end
    end
  end
end
