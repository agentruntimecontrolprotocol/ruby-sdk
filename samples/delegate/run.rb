# frozen_string_literal: true

require_relative 'server'
require_relative 'client'

code = Harness.run_or_exit('delegate') do |emit|
  server_t, client_t = Harness.pair_memory
  runtime = DelegateSample.runtime
  client, task = Harness.open_client(server_t, client_t, runtime, client_name: 'delegate')

  handle, events = DelegateSample::Client.run(client)
  delegate = events.find { _1.kind == Arcp::Job::EventKind::DELEGATE }

  emit.call(
    'job_id' => handle.job_id,
    'child_job_id' => delegate&.body&.child_job_id,
    'child_capabilities' => delegate&.body&.lease&.capabilities,
    'child_budget' => delegate&.body&.lease&.budget&.to_a
  )
  client.close
  task.stop
end
exit code
