---
title: Quickstart
sdk: ruby
kind: guide
order: 0
spec_sections: [§6, §7]
---

# Quickstart

A complete standalone tutorial — server and client in one process,
backed by `MemoryTransport`.

## Install

```ruby
# Gemfile
gem 'arcp', '~> 1.0'
```

```
bundle install
```

## The full script

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

## Next steps

- `guides/deployment.md` — running under falcon over WebSocket.
- `guides/agent-versioning.md` — `name@version` agent refs.
- `guides/result-streaming.md` — `result_chunk` for large outputs.
- `guides/budgets.md` — `cost.budget` accounting.
