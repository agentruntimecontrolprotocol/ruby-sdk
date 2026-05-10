# frozen_string_literal: true

require 'securerandom'

module Arcp
  # Crockford base32 alphabet for ULID-like ids.
  ULID_ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ'
  private_constant :ULID_ALPHABET

  # Generates a 26-character Crockford-base32 ULID-like identifier:
  # 48 bits of millisecond timestamp followed by 80 bits of randomness.
  #
  # @return [String] a sortable unique 26-char id
  def self.ulid
    encode_b32((Time.now.to_f * 1000).floor, 10) + encode_b32(SecureRandom.random_number(1 << 80), 16)
  end

  # @api private
  def self.encode_b32(value, length)
    chars = String.new(capacity: length)
    while length.positive?
      chars << ULID_ALPHABET[value & 31]
      value >>= 5
      length -= 1
    end
    chars.reverse!
    chars
  end
  private_class_method :encode_b32

  # Base class for typed identifiers.
  #
  # Each id type is a `Data.define(:value)` with validation in
  # `initialize`. Two id objects of different classes never compare equal
  # even when their string values match — `case/in` and `is_a?` discriminate.
  #
  # @example
  #   Arcp::SessionId.random         # => #<Arcp::SessionId value="01HZX...">
  #   Arcp::SessionId.new(value: 'sess_1') == Arcp::MessageId.new(value: 'sess_1') # => false
  module IdBuilder
    PREFIXES = {
      'SessionId' => 'sess_',
      'MessageId' => 'msg_',
      'JobId' => 'job_',
      'StreamId' => 'str_',
      'SubscriptionId' => 'sub_',
      'ArtifactId' => 'art_',
      'LeaseId' => 'lease_',
      'TraceId' => 'trace_',
      'SpanId' => 'span_'
    }.freeze

    def self.build(name)
      prefix = PREFIXES.fetch(name)
      Data.define(:value) do
        define_singleton_method(:random) do
          new(value: prefix + Arcp.ulid)
        end

        define_singleton_method(:type_name) { name }

        define_method(:initialize) do |value:|
          raise ArgumentError, "#{name} value must be a String" unless value.is_a?(String)
          raise ArgumentError, "#{name} value must not be blank" if value.strip.empty?

          super(value: value)
        end

        define_method(:to_s) { value }
        define_method(:to_str) { value }
        define_method(:to_json) { |*args| value.to_json(*args) }
        define_method(:as_json) { value }
      end
    end
  end

  SessionId      = IdBuilder.build('SessionId')
  MessageId      = IdBuilder.build('MessageId')
  JobId          = IdBuilder.build('JobId')
  StreamId       = IdBuilder.build('StreamId')
  SubscriptionId = IdBuilder.build('SubscriptionId')
  ArtifactId     = IdBuilder.build('ArtifactId')
  LeaseId        = IdBuilder.build('LeaseId')
  TraceId        = IdBuilder.build('TraceId')
  SpanId         = IdBuilder.build('SpanId')
end
