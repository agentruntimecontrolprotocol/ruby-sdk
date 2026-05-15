# frozen_string_literal: true

require_relative 'server'
require_relative 'client'

code = Harness.run_or_exit('ack_backpressure') do |emit|
  server_t, client_t = Harness.pair_memory
  runtime = AckBackpressureSample.runtime
  client, task = Harness.open_client(server_t, client_t, runtime, client_name: 'ack-backpressure')

  handle, events = AckBackpressureSample::Client.run(client)
  buffer_size = runtime.event_log.buffer_size(client.session.id)
  emit.call(
    'job_id' => handle.job_id,
    'received' => events.size,
    'buffer_size_after_ack' => buffer_size
  )
  client.close
  task.stop
end
exit code
