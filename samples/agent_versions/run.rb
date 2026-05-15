# frozen_string_literal: true

require_relative 'server'
require_relative 'client'

code = Harness.run_or_exit('agent_versions') do |emit|
  server_t, client_t = Harness.pair_memory
  runtime = AgentVersionsSample.runtime
  client, task = Harness.open_client(server_t, client_t, runtime, client_name: 'agent-versions')

  default, pinned, missing = AgentVersionsSample::Client.run(client)

  emit.call(
    'default_agent' => default.agent,
    'pinned_agent' => pinned.agent,
    'missing_code' => missing&.code
  )
  client.close
  task.stop
end
exit code
