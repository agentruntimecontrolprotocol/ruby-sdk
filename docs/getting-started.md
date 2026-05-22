---
title: Getting started
sdk: ruby
kind: guide
order: 0
spec_sections: [§6, §7]
---

# Getting started

Install `arcp` (Ruby 3.3+):

```ruby
# Gemfile
gem 'arcp', '~> 1.0'
```

```
bundle install
```

## Minimal in-process example

The handler, runtime, transport, and client all run in one process backed
by `MemoryTransport`. This is the fastest way to validate an integration
without a network or external server.

```ruby
require 'async'
require 'arcp'

ECHO_HANDLER = lambda do |ctx|
  ctx.log(level: 'info', message: "echoing #{ctx.input.inspect}")
  ctx.progress(current: 1, total: 1, units: 'message')
  ctx.finish(result: { 'echoed' => ctx.input })
end

Sync do
  # 1. Build the runtime.
  runtime = Arcp::Runtime::Runtime.new(
    auth_verifier: Arcp::Auth::Bearer.from_token('demo', principal_id: 'alice'),
    heartbeat_interval_sec: nil
  )
  runtime.register_agent(
    name: 'echo', versions: ['1.0.0'], default: '1.0.0',
    handler: ECHO_HANDLER
  )

  # 2. Wire an in-process transport pair.
  server_t, client_t = Arcp::Transport::MemoryTransport.pair
  server = Async { runtime.accept(server_t) }

  # 3. Open a session.
  client = Arcp::Client.open(
    transport: client_t,
    auth: { 'scheme' => 'bearer', 'token' => 'demo' },
    client_name: 'quickstart'
  )

  # 4. Submit, observe, collect.
  handle = client.submit_job(agent: 'echo', input: { 'msg' => 'hi' })
  events = handle.subscribe(client: client).to_a
  result = handle.get_result(client: client)

  puts "job_id:        #{handle.job_id}"
  puts "events:        #{events.map(&:kind).inspect}"
  puts "final_status:  #{result.final_status}"
  puts "result:        #{result.result.inspect}"

  # 5. Tear down.
  client.close
  server.stop
end
```

## What you should see

```
job_id:        job_...
events:        ["log", "progress"]
final_status:  success
result:        {"echoed"=>{"msg"=>"hi"}}
```

## Submit

```ruby
handle = client.submit_job(agent: 'echo', input: { 'msg' => 'hi' })
```

`handle` is an `Arcp::Job::Handle` with `job_id`, `agent`, `submitted_at`,
and `lease`.

## Subscribe

```ruby
handle.subscribe(client: client).each do |event|
  puts event.kind
end
```

Returns an `Enumerator` yielding `Arcp::Job::Event` values. The stream
terminates after the job's terminal `job.result` or `job.error`.

## Cancel

```ruby
handle.cancel(client: client, reason: 'user requested stop')
```

The job resolves to `Arcp::Errors::Cancelled` raised from `get_result`.

## List

```ruby
client.list_jobs(status: 'succeeded', limit: 25).each do |summary|
  puts summary.job_id
end
```

Returns a lazy `Enumerator` that walks `next_cursor` automatically.

## Next

- [architecture.md](architecture.md) — namespace map and concurrency model.
- [transports.md](transports.md) — which transport to pick.
- [guides/sessions.md](guides/sessions.md) — session lifecycle and capability negotiation.
- [guides/jobs.md](guides/jobs.md) — FSM, Handle API, idempotency, cancellation.
- [guides/deployment.md](guides/deployment.md) — running under Falcon over WebSocket.
