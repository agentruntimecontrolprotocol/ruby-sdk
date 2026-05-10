# frozen_string_literal: true

require 'arcp/error'

module Arcp
  # Extension mechanism (§21).
  #
  # Extension types and envelope fields must be namespaced as either:
  #
  # - `arcpx.<vendor>.<name>.v<n>`   — community/vendor namespace
  # - reverse-DNS, e.g. `com.acme.workflow.v2`
  #
  # The bare `x-` prefix is reserved for transport-internal experimental
  # fields and is rejected.
  module Extensions
    ARCPX_PATTERN     = /\Aarcpx(?:\.[a-z][a-z0-9-]*){2,}\.v\d+\z/
    REVERSE_DNS       = /\A[a-z][a-z0-9-]*(?:\.[a-z][a-z0-9-]*){2,}\.v\d+\z/
    private_constant :ARCPX_PATTERN, :REVERSE_DNS

    # Whether `value` looks like a valid extension namespace.
    #
    # @param value [String]
    # @return [Boolean]
    def self.namespaced?(value)
      return false unless value.is_a?(String)

      ARCPX_PATTERN.match?(value) || REVERSE_DNS.match?(value)
    end

    # Validate a candidate extension type or field name.
    #
    # @param value [String]
    # @raise [Arcp::Error::InvalidArgument]
    def self.validate!(value)
      return if namespaced?(value)
      if value.is_a?(String) && value.start_with?('x-')
        raise Error::InvalidArgument,
              "bare x- prefix not permitted (§21.1): #{value.inspect}"
      end

      raise Error::InvalidArgument, "not a valid extension namespace (§21.1): #{value.inspect}"
    end
  end

  # Negotiated extension registry per session (§21.2).
  #
  # A session-scoped registry of extension types the peer advertised in
  # `capabilities.extensions`. Used to decide whether an incoming
  # extension type is recognized.
  class ExtensionRegistry
    def initialize(advertised: [])
      @advertised = []
      advertised.each { |x| advertise!(x) }
    end

    # Advertise an extension namespace.
    #
    # @param namespace [String]
    # @raise [Arcp::Error::InvalidArgument]
    def advertise!(namespace)
      Extensions.validate!(namespace)
      @advertised << namespace unless @advertised.include?(namespace)
    end

    # @return [Array<String>]
    def advertised
      @advertised.dup
    end

    # @param type_or_field [String]
    # @return [Boolean]
    def supports?(type_or_field)
      @advertised.any? { |ns| type_or_field == ns || type_or_field.start_with?("#{ns}.") }
    end
  end
end
