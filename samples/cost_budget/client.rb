# frozen_string_literal: true

require_relative '../_harness'

module CostBudgetSample
  module Client
    def self.run(client)
      handle = client.submit_job(
        agent: 'shopper',
        lease_request: Arcp::Lease::LeaseRequest.new(
          capabilities: ['cost.spend'],
          budget: Arcp::Lease::CostBudget.parse(['USD:1.00']),
          expires_at: nil
        )
      )
      handle.subscribe(client: client).to_a
      error = begin
        handle.get_result(client: client)
        nil
      rescue Arcp::Errors::BudgetExhausted => e
        e
      end
      [handle, error]
    end
  end
end
