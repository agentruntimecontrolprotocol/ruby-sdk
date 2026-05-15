# frozen_string_literal: true

require 'spec_helper'
require 'bigdecimal'

RSpec.describe 'cost.budget enforcement', type: :integration do
  it 'exhausts a per-currency budget and raises BudgetExhausted' do
    Sync do
      lease_manager_ref = nil
      runtime = build_runtime(
        agents: { spender: ->(ctx) {
          # Spend three times against a $1.00 budget; third call should raise.
          3.times { lease_manager_ref.try_spend!(ctx.job_id, 'USD', BigDecimal('0.40')) }
          ctx.finish(result: 'ok')
        } }
      )
      lease_manager_ref = runtime.lease_manager

      client, server_task = open_pair(runtime)
      handle = client.submit_job(
        agent: 'spender',
        lease_request: Arcp::Lease::LeaseRequest.new(
          capabilities: ['cost.spend'],
          budget: Arcp::Lease::CostBudget.parse(['USD:1.00']),
          expires_at: nil
        )
      )
      handle.subscribe(client: client).to_a
      expect { handle.get_result(client: client) }.to raise_error(Arcp::Errors::BudgetExhausted)
      client.close
      server_task.stop
    end
  end
end
