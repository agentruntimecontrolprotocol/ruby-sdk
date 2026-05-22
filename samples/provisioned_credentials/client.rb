# frozen_string_literal: true

require_relative '../_harness'

module ProvisionedCredentialsSample
  module Client
    def self.run(client)
      handle = client.submit_job(
        agent: 'gateway-caller',
        lease_request: Arcp::Lease::LeaseRequest.new(
          capabilities: ['cost.spend'],
          budget: Arcp::Lease::CostBudget.parse(['USD:1.00']),
          model_use: ['tier-fast/*']
        )
      )
      result = handle.get_result(client: client)
      [handle, result]
    end
  end
end
