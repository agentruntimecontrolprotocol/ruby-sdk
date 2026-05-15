# frozen_string_literal: true

require_relative 'server'
require_relative 'client'

code = Harness.run_or_exit('subscribe') do |emit|
  runtime = SubscribeSample.runtime
  server_a, client_a = Harness.pair_memory
  server_b, client_b = Harness.pair_memory

  task_a = Async { runtime.accept(server_a) }
  task_b = Async { runtime.accept(server_b) }

  alice = Arcp::Client.open(transport: client_a, auth: { 'token' => 'demo' }, client_name: 'alice')
  alice_observer = Arcp::Client.open(transport: client_b, auth: { 'token' => 'demo' }, client_name: 'alice-observer')

  handle, events = SubscribeSample::Client.run(alice, alice_observer)

  emit.call(
    'job_id' => handle.job_id,
    'observed_kinds' => events.map(&:kind)
  )
  alice.close
  alice_observer.close
  task_a.stop
  task_b.stop
end
exit code
