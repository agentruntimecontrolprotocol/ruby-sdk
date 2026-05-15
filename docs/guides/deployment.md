---
title: Deployment
sdk: ruby
kind: guide
order: 30
---

# Deployment

The runtime is fiber-based. It runs as a daemon under
`socketry/async`, and exposes a WebSocket endpoint under `falcon`.

## Topology

```
client (browser, CLI, other service)
  -- WebSocket arcp.v1 -->
falcon (HTTPS + WS)
  -- per-connection WebSocketTransport -->
Arcp::Runtime::Runtime (one process, many sessions)
```

## Falcon entry point

`config.ru`:

```ruby
require 'async'
require 'async/websocket/adapters/rack'
require 'arcp'

RUNTIME = Arcp::Runtime::Runtime.new(
  auth_verifier: Arcp::Auth::Bearer.new(tokens: load_tokens),
  heartbeat_interval_sec: 30,
  resume_window_sec: 300
)
RUNTIME.register_agent(
  name: 'echo', versions: ['1.0.0'], default: '1.0.0',
  handler: ->(ctx) { ctx.finish(result: ctx.input) }
)

run lambda { |env|
  Async::WebSocket::Adapters::Rack.open(env, protocols: ['arcp.v1']) do |conn|
    transport = Arcp::Transport::WebSocketTransport.new(connection: conn)
    RUNTIME.accept(transport)
  end or [404, {}, ['not a websocket']]
}
```

Run with:

```
bundle exec falcon serve --bind https://0.0.0.0:9292 config.ru
```

## What not to do

- Don't deploy under Puma, Unicorn, or any request-per-thread server.
  The runtime expects long-lived fiber-multiplexed connections; a
  thread-per-request worker pool will starve under load.
- Don't share one `Arcp::Client` across processes or threads. A client
  owns a transport and a session — open one per connection.
- Don't block the reactor with synchronous I/O inside a handler. Use
  `async-http`, `async-redis`, or wrap blocking calls in
  `Async::Task.current.with_timeout` and a thread pool.

## Process supervision

The runtime has no built-in supervisor. Run `falcon` under systemd,
runit, or your platform's process manager. On SIGTERM, call
`runtime.shutdown(reason: 'shutdown')` to send `session.bye` to every
attached session before exiting.

## Resource limits

- `resume_window_sec` bounds the event log retention; bigger windows
  cost more memory.
- Each session holds a small per-job queue. Jobs that finish are
  released once all subscribers drain.
