# frozen_string_literal: true

require_relative '../_harness'

code = Harness.run_or_exit('heartbeat') do |emit|
  server_t, client_t = Harness.pair_memory
  runtime = Harness.runtime(
    agents: { 'idle' => ->(ctx) { Async::Task.current.sleep(0.5); ctx.finish } },
    heartbeat_interval_sec: 0.05
  )
  client, task = Harness.open_client(server_t, client_t, runtime, client_name: 'heartbeat')

  handle = client.submit_job(agent: 'idle')
  # Give the heartbeat loop two ticks.
  Async::Task.current.sleep(0.15)

  emit.call(
    'heartbeat_interval' => client.session.heartbeat_interval_sec,
    'session_supports_heartbeat' => client.session.supports?(Arcp::Session::Feature::HEARTBEAT),
    'job_id' => handle.job_id
  )
  client.close
  task.stop
end
exit code
