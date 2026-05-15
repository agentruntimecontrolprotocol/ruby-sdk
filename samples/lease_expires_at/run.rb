# frozen_string_literal: true

require_relative 'server'
require_relative 'client'

code = Harness.run_or_exit('lease_expires_at') do |emit|
  server_t, client_t = Harness.pair_memory
  runtime = LeaseExpiresAtSample.runtime
  client, task = Harness.open_client(server_t, client_t, runtime, client_name: 'lease-expires-at')

  handle, deadline, error = LeaseExpiresAtSample::Client.run(client)
  emit.call(
    'job_id' => handle.job_id,
    'deadline' => deadline,
    'expired' => !error.nil?,
    'code' => error&.code
  )
  client.close
  task.stop
end
exit code
