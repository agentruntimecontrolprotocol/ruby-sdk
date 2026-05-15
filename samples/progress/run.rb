# frozen_string_literal: true

require_relative 'server'
require_relative 'client'

code = Harness.run_or_exit('progress') do |emit|
  server_t, client_t = Harness.pair_memory
  runtime = ProgressSample.runtime
  client, task = Harness.open_client(server_t, client_t, runtime, client_name: 'progress')

  handle, progress = ProgressSample::Client.run(client)
  rendered = progress.map { |e| "#{e.body.current}/#{e.body.total}" }
  rendered.each { |line| Harness::StderrLogger.info(line) }

  emit.call(
    'job_id' => handle.job_id,
    'rendered' => rendered,
    'count' => progress.size
  )
  client.close
  task.stop
end
exit code
