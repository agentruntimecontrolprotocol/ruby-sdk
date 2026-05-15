# frozen_string_literal: true

require_relative '../_harness'

module DelegateSample
  module Client
    def self.run(client)
      handle = client.submit_job(
        agent: 'parent',
        lease_request: Arcp::Lease::LeaseRequest.new(
          capabilities: %w[compute.read compute.write],
          budget: Arcp::Lease::CostBudget.parse(['USD:5.00']),
          expires_at: nil
        )
      )
      events = handle.subscribe(client: client).to_a
      [handle, events]
    end
  end
end
