# frozen_string_literal: true

require_relative 'server'
require_relative 'client'

code = Harness.run_or_exit('idempotent_retry') do |emit|
  server_t, client_t = Harness.pair_memory
  runtime = IdempotentRetrySample.runtime
  client, task = Harness.open_client(server_t, client_t, runtime, client_name: 'idempotent-retry')

  first, second, conflict = IdempotentRetrySample::Client.run(client)
  emit.call(
    'first_job_id' => first.job_id,
    'second_job_id' => second.job_id,
    'same_job_id' => first.job_id == second.job_id,
    'conflict_code' => conflict&.code
  )
  client.close
  task.stop
end
exit code
