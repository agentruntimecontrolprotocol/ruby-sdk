# frozen_string_literal: true

require_relative 'server'
require_relative 'client'

code = Harness.run_or_exit('cost_budget') do |emit|
  server_t, client_t = Harness.pair_memory
  runtime = CostBudgetSample.runtime
  client, task = Harness.open_client(server_t, client_t, runtime, client_name: 'cost-budget')

  handle, error = CostBudgetSample::Client.run(client)
  emit.call(
    'job_id' => handle.job_id,
    'exhausted' => !error.nil?,
    'remaining' => error&.details&.dig('remaining')
  )
  client.close
  task.stop
end
exit code
