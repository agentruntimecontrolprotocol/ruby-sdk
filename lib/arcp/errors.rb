# frozen_string_literal: true

module Arcp
  class Error < StandardError
    CODE = 'INTERNAL_ERROR'

    attr_reader :details

    def initialize(message = nil, details: {})
      @details = details.freeze
      super(message || self.class.default_message)
    end

    def code = self.class::CODE
    def retryable? = false

    def to_payload(trace_id: nil)
      payload = { code: code, message: message, retryable: retryable? }
      payload[:details] = details unless details.empty?
      payload[:trace_id] = trace_id if trace_id
      payload
    end

    # @api private
    def self.default_message = name.split('::').last.gsub(/([a-z])([A-Z])/, '\1 \2').downcase
  end

  module Errors
    class Cancelled < Arcp::Error
      CODE = 'CANCELLED'
    end

    class InvalidRequest < Arcp::Error
      CODE = 'INVALID_REQUEST'
    end

    class Unauthenticated < Arcp::Error
      CODE = 'UNAUTHENTICATED'
    end

    class PermissionDenied < Arcp::Error
      CODE = 'PERMISSION_DENIED'
    end

    class JobNotFound < Arcp::Error
      CODE = 'JOB_NOT_FOUND'
    end

    class AgentNotAvailable < Arcp::Error
      CODE = 'AGENT_NOT_AVAILABLE'
      def retryable? = true
    end

    class DuplicateKey < Arcp::Error
      CODE = 'DUPLICATE_KEY'
    end

    class RateLimited < Arcp::Error
      CODE = 'RATE_LIMITED'
      def retryable? = true
    end

    class Internal < Arcp::Error
      CODE = 'INTERNAL_ERROR'
      def retryable? = true
    end

    class HeartbeatLost < Arcp::Error
      CODE = 'HEARTBEAT_LOST'
      def retryable? = true
    end

    class Backpressure < Arcp::Error
      CODE = 'BACKPRESSURE'
      def retryable? = true
    end

    class ProtocolViolation < Arcp::Error
      CODE = 'PROTOCOL_VIOLATION'
    end

    class Timeout < Arcp::Error
      CODE = 'TIMEOUT'
      def retryable? = true
    end

    class ResumeWindowExpired < Arcp::Error
      CODE = 'RESUME_WINDOW_EXPIRED'
    end

    class LeaseSubsetViolation < Arcp::Error
      CODE = 'LEASE_SUBSET_VIOLATION'
    end

    class AgentVersionNotAvailable < Arcp::Error
      CODE = 'AGENT_VERSION_NOT_AVAILABLE'
    end

    class LeaseExpired < Arcp::Error
      CODE = 'LEASE_EXPIRED'
    end

    class BudgetExhausted < Arcp::Error
      CODE = 'BUDGET_EXHAUSTED'
    end

    # Library-internal: never appears on the wire.
    class UnnegotiatedFeature < Arcp::Error
      CODE = 'UNNEGOTIATED_FEATURE'
    end

    ALL = [
      Cancelled, InvalidRequest, Unauthenticated, PermissionDenied,
      JobNotFound, AgentNotAvailable, DuplicateKey, RateLimited,
      Internal, HeartbeatLost, Backpressure, ProtocolViolation, Timeout,
      ResumeWindowExpired, LeaseSubsetViolation,
      AgentVersionNotAvailable, LeaseExpired, BudgetExhausted
    ].freeze

    WIRE_CODES = ALL.map { |c| c::CODE }.freeze

    BY_CODE = ALL.to_h { |klass| [klass::CODE, klass] }.freeze

    RETRYABLE_BY_DEFAULT = ALL.select { |k| k.new.retryable? }.map { |k| k::CODE }.freeze
    NON_RETRYABLE_BY_DEFAULT = (WIRE_CODES - RETRYABLE_BY_DEFAULT).freeze

    def self.for(code, message: nil, details: {})
      klass = BY_CODE[code] || Arcp::Errors::Internal
      klass.new(message, details: details)
    end
  end

  module ErrorCode
    CANCELLED                    = 'CANCELLED'
    INVALID_REQUEST              = 'INVALID_REQUEST'
    UNAUTHENTICATED              = 'UNAUTHENTICATED'
    PERMISSION_DENIED            = 'PERMISSION_DENIED'
    JOB_NOT_FOUND                = 'JOB_NOT_FOUND'
    AGENT_NOT_AVAILABLE          = 'AGENT_NOT_AVAILABLE'
    DUPLICATE_KEY                = 'DUPLICATE_KEY'
    RATE_LIMITED                 = 'RATE_LIMITED'
    INTERNAL_ERROR               = 'INTERNAL_ERROR'
    HEARTBEAT_LOST               = 'HEARTBEAT_LOST'
    BACKPRESSURE                 = 'BACKPRESSURE'
    PROTOCOL_VIOLATION           = 'PROTOCOL_VIOLATION'
    TIMEOUT                      = 'TIMEOUT'
    RESUME_WINDOW_EXPIRED        = 'RESUME_WINDOW_EXPIRED'
    LEASE_SUBSET_VIOLATION       = 'LEASE_SUBSET_VIOLATION'
    AGENT_VERSION_NOT_AVAILABLE  = 'AGENT_VERSION_NOT_AVAILABLE'
    LEASE_EXPIRED                = 'LEASE_EXPIRED'
    BUDGET_EXHAUSTED             = 'BUDGET_EXHAUSTED'

    ALL = Arcp::Errors::WIRE_CODES
  end
end
