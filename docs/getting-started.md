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
gem 'arcp', '~> 1.0'
```

## Minimal in-process example

```ruby
require 'async'
require 'arcp'

Sync do
  runtime = Arcp::Runtime::Runtime.new(
    auth_verifier: Arcp::Auth::Bearer.from_token('demo', principal_id: 'alice'),
    heartbeat_interval_sec: nil
  )
  runtime.register_agent(
    name: 'echo', versions: ['1.0.0'], default: '1.0.0',
    handler: ->(ctx) { ctx.finish(result: { 'echoed' => ctx.input }) }
  )

  server_t, client_t = Arcp::Transport::MemoryTransport.pair
  server = Async { runtime.accept(server_t) }
  client = Arcp::Client.open(
    transport: client_t,
    auth: { 'scheme' => 'bearer', 'token' => 'demo' }
  )

  handle = client.submit_job(agent: 'echo', input: { 'msg' => 'hi' })
  events = handle.subscribe(client: client).to_a
  result = handle.get_result(client: client)

  client.close
  server.stop
end
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

- `architecture.md` — namespace map and concurrency model.
- `transports.md` — which transport to pick.
- `concepts/sessions.md`, `concepts/jobs.md` — protocol concepts.
