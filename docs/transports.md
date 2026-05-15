---
title: Transports
sdk: ruby
kind: reference
order: 2
spec_sections: [§5]
---

# Transports

A transport implements four methods: `send(envelope)`, `receive`,
`close(reason:)`, `closed?`. Three implementations ship with the SDK.

## MemoryTransport

In-process queue pair. Use for tests, embedded clients, and same-process
demos.

```ruby
server_t, client_t = Arcp::Transport::MemoryTransport.pair
server = Async { runtime.accept(server_t) }
client = Arcp::Client.open(transport: client_t, auth: { 'scheme' => 'bearer', 'token' => 'demo' })
```

No serialization happens — envelopes pass as Ruby objects. Asserts about
the wire encoding need a real JSON transport.

## WebSocketTransport

Wraps an open `Async::WebSocket::Connection`. Use for production. The
SDK does not include a server; pair with `falcon` and `async-websocket`.

```ruby
require 'async/websocket'

Async::WebSocket::Client.connect(endpoint, protocols: ['arcp.v1']) do |conn|
  transport = Arcp::Transport::WebSocketTransport.new(connection: conn)
  client = Arcp::Client.open(
    transport: transport,
    auth: { 'scheme' => 'bearer', 'token' => ENV.fetch('ARCP_TOKEN') }
  )
  # ...
end
```

Each `send` writes one JSON envelope and flushes. Each `receive` reads
one message and decodes via `Arcp::Envelope.from_json`. EOF returns
`nil`.

## StdioTransport

Newline-delimited JSON over a pair of `IO`s. Use for co-process agents
spawned by a parent — the child reads stdin and writes stdout.

```ruby
transport = Arcp::Transport::StdioTransport.new
runtime.accept(transport)  # in the child process
```

The parent process pairs its end of the pipe to a `Client` and
communicates over the same NDJSON framing.

## Picking one

- Same process / tests: `MemoryTransport`
- Network: `WebSocketTransport` (under `falcon`)
- Child process: `StdioTransport`
