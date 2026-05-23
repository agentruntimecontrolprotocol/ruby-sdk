# frozen_string_literal: true

# email_vendor_leases client — submit triage with a lease that omits send_reply.

require_relative '../../samples/_harness'

module EmailVendorLeasesRecipe
  module Client
    def self.run(client)
      # the lease grants tool.call only for read-only inbox tools. send_reply
      # is intentionally absent — when Claude proposes that tool the agent's
      # lease check raises PermissionDenied and a tool_result error is fed
      # back. the model recovers and returns a drafted (not-sent) reply.
      handle = client.submit_job(
        agent: 'triage',
        lease_request: Arcp::Lease::LeaseRequest.new(
          capabilities: ['tool.call:inbox_list', 'tool.call:inbox_read'],
          budget: nil,
          model_use: nil,
          expires_at: nil
        )
      )
      events = handle.subscribe(client: client).to_a
      result = handle.get_result(client: client)
      [handle, events, result]
    end
  end
end
