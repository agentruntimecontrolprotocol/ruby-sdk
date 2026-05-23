# frozen_string_literal: true

# multi_agent_budget client — submit the top-level research question with a USD cap.

require_relative '../../samples/_harness'

module MultiAgentBudgetRecipe
  module Client
    def self.run(client)
      # workers each carve a slice from the planner's remaining budget. when
      # the budget no longer fits a grant the planner drops the sub-question;
      # when a worker overspends inside its own slice that worker job ends
      # with BudgetExhausted while siblings continue.
      handle = client.submit_job(
        agent: 'planner',
        input: { 'question' => 'What causes urban heat islands?' },
        lease_request: Arcp::Lease::LeaseRequest.new(
          capabilities: ['tool.call:llm.complete', 'agent.delegate:worker'],
          budget: Arcp::Lease::CostBudget.parse(['USD:0.50']),
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
