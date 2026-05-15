# frozen_string_literal: true

require_relative 'server'
require_relative 'client'

code = Harness.run_or_exit('list_jobs') do |emit|
  server_t, client_t = Harness.pair_memory
  runtime = ListJobsSample.runtime
  client, task = Harness.open_client(server_t, client_t, runtime, client_name: 'list-jobs')

  handles, pages = ListJobsSample::Client.run(client, count: 5)
  emit.call(
    'submitted' => handles.size,
    'listed' => pages.size,
    'agents' => pages.map(&:agent).uniq
  )
  client.close
  task.stop
end
exit code
