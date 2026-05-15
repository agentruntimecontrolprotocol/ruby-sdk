# frozen_string_literal: true

require_relative 'server'
require_relative 'client'

code = Harness.run_or_exit('lease_violation') do |emit|
  server_t, client_t = Harness.pair_memory
  runtime = LeaseViolationSample.runtime
  client, task = Harness.open_client(server_t, client_t, runtime, client_name: 'lease-violation')

  handle, events, result = LeaseViolationSample::Client.run(client)
  tool_results = events.select { _1.kind == Arcp::Job::EventKind::TOOL_RESULT }

  emit.call(
    'job_id' => handle.job_id,
    'final_status' => result.final_status,
    'tool_result_errors' => tool_results.map { _1.body.error['code'] }
  )
  client.close
  task.stop
end
exit code
