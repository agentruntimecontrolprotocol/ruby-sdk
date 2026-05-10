# frozen_string_literal: true

require 'arcp/error_code'

module Arcp
  # Base class for ARCP errors.
  #
  # Public APIs raise specific subclasses of `Arcp::Error`; pattern-match
  # on the class to dispatch on the canonical error code.
  class Error < StandardError
    # Canonical error code (§18.2).
    #
    # @return [String]
    def code
      ErrorCode::UNKNOWN
    end

    # Whether this error is retryable per §18.3 by default.
    #
    # @return [Boolean]
    def retryable?
      ErrorCode.retryable?(code)
    end

    # Structured details suitable for inclusion in a tool.error or nack
    # payload. Override in subclasses to add fields.
    #
    # @return [Hash]
    def details
      {}
    end

    # Marshal this exception to a tool.error/nack payload (§18.1).
    #
    # @param trace_id [String, nil]
    # @return [Hash]
    def to_payload(trace_id: nil)
      payload = {
        code: code,
        message: message,
        retryable: retryable?
      }
      detail_hash = details
      payload[:details] = detail_hash unless detail_hash.empty?
      payload[:trace_id] = trace_id if trace_id
      payload
    end

    class Cancelled < self
      def code = ErrorCode::CANCELLED
    end

    class InvalidArgument < self
      def code = ErrorCode::INVALID_ARGUMENT
    end

    class DeadlineExceeded < self
      def code = ErrorCode::DEADLINE_EXCEEDED
    end

    class NotFound < self
      def code = ErrorCode::NOT_FOUND
    end

    class AlreadyExists < self
      def code = ErrorCode::ALREADY_EXISTS
    end

    class PermissionDenied < self
      attr_reader :permission, :resource

      def initialize(message = nil, permission: nil, resource: nil)
        @permission = permission
        @resource = resource
        super(message || "permission denied: #{permission} on #{resource}")
      end

      def code = ErrorCode::PERMISSION_DENIED

      def details
        d = {}
        d[:permission] = permission if permission
        d[:resource] = resource if resource
        d
      end
    end

    class ResourceExhausted < self
      attr_reader :retry_after_seconds

      def initialize(message = 'resource exhausted', retry_after_seconds: nil)
        @retry_after_seconds = retry_after_seconds
        super(message)
      end

      def code = ErrorCode::RESOURCE_EXHAUSTED

      def details
        retry_after_seconds ? { retry_after_seconds: retry_after_seconds } : {}
      end
    end

    class FailedPrecondition < self
      def code = ErrorCode::FAILED_PRECONDITION
    end

    class Aborted < self
      def code = ErrorCode::ABORTED
    end

    class OutOfRange < self
      def code = ErrorCode::OUT_OF_RANGE
    end

    class Unimplemented < self
      attr_reader :section, :detail

      def initialize(section:, detail:)
        @section = section
        @detail = detail
        super("unimplemented (RFC #{section}): #{detail}")
      end

      def code = ErrorCode::UNIMPLEMENTED
      def details = { section: section, detail: detail }
    end

    class Internal < self
      def code = ErrorCode::INTERNAL
    end

    class Unavailable < self
      def code = ErrorCode::UNAVAILABLE
    end

    class DataLoss < self
      def code = ErrorCode::DATA_LOSS
    end

    class Unauthenticated < self
      def code = ErrorCode::UNAUTHENTICATED
    end

    class HeartbeatLost < self
      def code = ErrorCode::HEARTBEAT_LOST
    end

    class LeaseExpired < self
      attr_reader :lease_id, :expired_at

      def initialize(lease_id:, expired_at:)
        @lease_id = lease_id
        @expired_at = expired_at
        super("lease #{lease_id} expired at #{expired_at}")
      end

      def code = ErrorCode::LEASE_EXPIRED
      def details = { lease_id: lease_id.to_s, expired_at: expired_at.iso8601 }
    end

    class LeaseRevoked < self
      attr_reader :lease_id, :reason

      def initialize(lease_id:, reason: nil)
        @lease_id = lease_id
        @reason = reason
        super("lease #{lease_id} revoked#{": #{reason}" if reason}")
      end

      def code = ErrorCode::LEASE_REVOKED

      def details
        d = { lease_id: lease_id.to_s }
        d[:reason] = reason if reason
        d
      end
    end

    class BackpressureOverflow < self
      def code = ErrorCode::BACKPRESSURE_OVERFLOW
    end

    # Raised when an envelope cannot be parsed off the wire.
    class ParseError < self
      def code = ErrorCode::INVALID_ARGUMENT
    end
  end
end
