# frozen_string_literal: true

require_relative 'server'
require_relative 'client'

code = Harness.run_or_exit('multi_agent_budget') do |emit|
  server_t, client_t = Harness.pair_memory
  runtime = MultiAgentBudgetRecipe.runtime
  client, task = Harness.open_client(server_t, client_t, runtime, client_name: 'multi-agent-budget')

  handle, events, result = MultiAgentBudgetRecipe::Client.run(client)
  delegated = events.select { |e| e.kind == Arcp::Job::EventKind::DELEGATE }

  emit.call(
    'job_id' => handle.job_id,
    'final_status' => result.final_status,
    'delegated_count' => delegated.size,
    'dropped_count' => (result.result&.dig('dropped') || []).size
  )
  client.close
  task.stop
end
exit code
