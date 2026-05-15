# frozen_string_literal: true

require_relative 'server'
require_relative 'client'

code = Harness.run_or_exit('cancel') do |emit|
  server_t, client_t = Harness.pair_memory
  runtime = CancelSample.runtime
  client, task = Harness.open_client(server_t, client_t, runtime, client_name: 'cancel')

  handle, error = CancelSample::Client.run(client)
  emit.call(
    'job_id' => handle.job_id,
    'cancelled' => !error.nil?,
    'error_code' => error&.code
  )
  client.close
  task.stop
end
exit code
