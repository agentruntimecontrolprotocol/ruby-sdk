# frozen_string_literal: true

module Arcp
  # Canonical ARCP error codes (§18.2).
  #
  # Implementations must use these codes when applicable; deployment-
  # specific codes must be namespaced (e.g. `arcpx.acme.QUOTA_EXCEEDED`).
  module ErrorCode
    OK                    = 'OK'
    CANCELLED             = 'CANCELLED'
    UNKNOWN               = 'UNKNOWN'
    INVALID_ARGUMENT      = 'INVALID_ARGUMENT'
    DEADLINE_EXCEEDED     = 'DEADLINE_EXCEEDED'
    NOT_FOUND             = 'NOT_FOUND'
    ALREADY_EXISTS        = 'ALREADY_EXISTS'
    PERMISSION_DENIED     = 'PERMISSION_DENIED'
    RESOURCE_EXHAUSTED    = 'RESOURCE_EXHAUSTED'
    FAILED_PRECONDITION   = 'FAILED_PRECONDITION'
    ABORTED               = 'ABORTED'
    OUT_OF_RANGE          = 'OUT_OF_RANGE'
    UNIMPLEMENTED         = 'UNIMPLEMENTED'
    INTERNAL              = 'INTERNAL'
    UNAVAILABLE           = 'UNAVAILABLE'
    DATA_LOSS             = 'DATA_LOSS'
    UNAUTHENTICATED       = 'UNAUTHENTICATED'
    HEARTBEAT_LOST        = 'HEARTBEAT_LOST'
    LEASE_EXPIRED         = 'LEASE_EXPIRED'
    LEASE_REVOKED         = 'LEASE_REVOKED'
    BACKPRESSURE_OVERFLOW = 'BACKPRESSURE_OVERFLOW'

    ALL = [
      OK, CANCELLED, UNKNOWN, INVALID_ARGUMENT, DEADLINE_EXCEEDED, NOT_FOUND,
      ALREADY_EXISTS, PERMISSION_DENIED, RESOURCE_EXHAUSTED, FAILED_PRECONDITION,
      ABORTED, OUT_OF_RANGE, UNIMPLEMENTED, INTERNAL, UNAVAILABLE, DATA_LOSS,
      UNAUTHENTICATED, HEARTBEAT_LOST, LEASE_EXPIRED, LEASE_REVOKED,
      BACKPRESSURE_OVERFLOW
    ].freeze

    RETRYABLE_BY_DEFAULT = [
      RESOURCE_EXHAUSTED, UNAVAILABLE, DEADLINE_EXCEEDED, INTERNAL, ABORTED
    ].to_set.freeze

    NON_RETRYABLE_BY_DEFAULT = [
      INVALID_ARGUMENT, NOT_FOUND, ALREADY_EXISTS, PERMISSION_DENIED,
      FAILED_PRECONDITION, UNIMPLEMENTED, UNAUTHENTICATED, DATA_LOSS
    ].to_set.freeze

    # Whether the given canonical code is retryable per §18.3 by default.
    #
    # @param code [String]
    # @return [Boolean]
    def self.retryable?(code)
      RETRYABLE_BY_DEFAULT.include?(code)
    end
  end
end
