# frozen_string_literal: true

require 'arcp/error'
require 'arcp/error_code'
require 'arcp/ids'
require 'arcp/messages/permissions'

module Arcp
  module Runtime
    # Materialized lease record (§15.5).
    class LeaseRecord
      attr_reader :lease_id, :session_id, :permission, :resource, :operation, :expires_at, :state

      def initialize(lease_id:, session_id:, permission:, resource:, operation:, expires_at:)
        @lease_id = lease_id
        @session_id = session_id
        @permission = permission
        @resource = resource
        @operation = operation
        @expires_at = expires_at
        @state = :granted
      end

      def expired?(now)
        @state != :revoked && now >= @expires_at
      end

      def revoke!
        @state = :revoked
      end

      def extend!(new_expires_at)
        @expires_at = new_expires_at
      end
    end

    # Manages permission grants and lease lifecycle (§15.4, §15.5).
    class LeaseManager
      # @param emit [#call(record, payload)]
      # @param clock [#now]
      def initialize(emit:, clock: Time)
        @emit = emit
        @clock = clock
        @leases = {}
        @mutex = Mutex.new
      end

      # @return [Arcp::Runtime::LeaseRecord]
      def grant(session_id:, permission:, resource:, operation:, lease_seconds:)
        lease_id = LeaseId.random
        expires_at = @clock.now + lease_seconds
        record = LeaseRecord.new(
          lease_id: lease_id, session_id: session_id,
          permission: permission, resource: resource,
          operation: operation, expires_at: expires_at
        )
        @mutex.synchronize { @leases[lease_id.value] = record }
        @emit.call(record, Messages::Permissions::LeaseGranted.new(
                             lease_id: lease_id.value, permission: permission, resource: resource,
                             operation: operation, expires_at: expires_at.utc.iso8601(6)
                           ))
        record
      end

      def extend_lease(lease_id, extend_seconds:)
        record = @mutex.synchronize { @leases[id_value(lease_id)] }
        raise Arcp::Error::NotFound, "lease not found: #{lease_id}" if record.nil?

        new_expires = @clock.now + extend_seconds
        record.extend!(new_expires)
        @emit.call(record, Messages::Permissions::LeaseExtended.new(
                             lease_id: record.lease_id.value, expires_at: new_expires.utc.iso8601(6)
                           ))
        record
      end

      def revoke(lease_id, reason: nil)
        record = @mutex.synchronize { @leases[id_value(lease_id)] }
        return false if record.nil? || record.state == :revoked

        record.revoke!
        @emit.call(record, Messages::Permissions::LeaseRevoked.new(
                             lease_id: record.lease_id.value, reason: reason
                           ))
        true
      end

      # Validate that a lease is currently usable.
      #
      # @raise [Arcp::Error::LeaseExpired] if expired
      # @raise [Arcp::Error::LeaseRevoked] if revoked
      # @raise [Arcp::Error::NotFound] if absent
      def validate!(lease_id)
        record = @mutex.synchronize { @leases[id_value(lease_id)] }
        raise Arcp::Error::NotFound, "lease not found: #{lease_id}" if record.nil?
        raise Arcp::Error::LeaseRevoked.new(lease_id: record.lease_id) if record.state == :revoked
        if record.expired?(@clock.now)
          raise Arcp::Error::LeaseExpired.new(lease_id: record.lease_id,
                                              expired_at: record.expires_at)
        end

        record
      end

      def lookup(lease_id)
        @mutex.synchronize { @leases[id_value(lease_id)] }
      end

      private

      def id_value(lease_id)
        lease_id.respond_to?(:value) ? lease_id.value : lease_id
      end
    end
  end
end
