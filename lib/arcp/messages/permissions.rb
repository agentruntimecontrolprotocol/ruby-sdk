# frozen_string_literal: true

require 'arcp/messages/base'

module Arcp
  module Messages
    # Permissions and lease lifecycle payloads (§15).
    module Permissions
      PermissionRequest = Arcp::Messages.define('permission.request',
                                                required: %i[permission resource operation],
                                                optional: { reason: nil, requested_lease_seconds: 300 })
      PermissionGrant   = Arcp::Messages.define('permission.grant',
                                                required: %i[permission resource operation],
                                                optional: {
                                                  lease_seconds: 300,
                                                  attestation: nil
                                                })
      PermissionDeny    = Arcp::Messages.define('permission.deny',
                                                required: %i[permission resource operation],
                                                optional: { reason: nil })

      LeaseGranted = Arcp::Messages.define('lease.granted',
                                           required: %i[lease_id permission resource operation expires_at])
      LeaseRefresh = Arcp::Messages.define('lease.refresh',
                                           required: %i[lease_id],
                                           optional: { extend_seconds: 300 })
      LeaseExtended = Arcp::Messages.define('lease.extended',
                                            required: %i[lease_id expires_at])
      LeaseRevoked  = Arcp::Messages.define('lease.revoked',
                                            required: %i[lease_id],
                                            optional: { reason: nil })
    end
  end
end
