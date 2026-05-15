# frozen_string_literal: true

require_relative 'server'
require_relative 'client'

code = Harness.run_or_exit('submit_and_stream') do |emit|
  server_t, client_t = Harness.pair_memory
  runtime = SubmitAndStream::Server.runtime
  client, task = Harness.open_client(server_t, client_t, runtime, client_name: 'submit-and-stream')

  handle, events, result = SubmitAndStream::Client.run(client)
  Harness::StderrLogger.info("job #{handle.job_id} streamed #{events.size} events")

  emit.call(
    'job_id' => handle.job_id,
    'kinds' => events.map(&:kind),
    'final_status' => result.final_status,
    'result' => result.result
  )

  client.close
  task.stop
end
exit code
