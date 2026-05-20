# arcp

Ruby SDK for ARCP v1. The wire protocol is specified in
[../spec/docs/draft-arcp-1.1.md](../spec/docs/draft-arcp-1.1.md). This
gem implements the full v1 envelope, session handshake, job lifecycle,
event stream, leases, and error model.

## Install

```ruby
gem 'arcp', '~> 1.0'
```

Requires Ruby 3.3+. Runs on the `socketry/async` reactor; pairs with
`falcon` for hosting and `async-websocket` for the WebSocket transport.

## Quickstart

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
    handler: ->(ctx) {
      ctx.progress(current: 1, total: 1, units: 'message')
      ctx.finish(result: { 'echoed' => ctx.input })
    }
  )

  server_t, client_t = Arcp::Transport::MemoryTransport.pair
  server = Async { runtime.accept(server_t) }

  client = Arcp::Client.open(
    transport: client_t,
    auth: { 'scheme' => 'bearer', 'token' => 'demo' }
  )
  handle = client.submit_job(agent: 'echo', input: { 'msg' => 'hi' })
  handle.subscribe(client: client).each { |ev| puts ev.kind }
  puts handle.get_result(client: client).result.inspect

  client.close
  server.stop
end
```

## What is ARCP

ARCP is a session-oriented protocol for invoking remote agents. A client
opens a session, submits jobs, and receives a stream of structured events
followed by a terminal result or error. The protocol covers capability
negotiation, heartbeats, ordered acks, cursored job listing, cross-session
observation, capability-bounded leases, and trace propagation.

## Features

- Capability negotiation (§6.2)
- Heartbeat / ping-pong (§6.4)
- Application-level ack (§6.5)
- Cursored `list_jobs` (§6.6)
- Cross-session `job.subscribe` with history replay (§7.6)
- Agent versioning with `name@version` refs (§7.5)
- `result_chunk` streaming with result_id terminator (§8.4)
- `progress` events (§8.2)
- `lease_constraints.expires_at` (§9)
- `cost.budget` capability with `BigDecimal` arithmetic (§9.6)
- Resume token + last_event_seq replay (§6.3)
- Trace context propagation (§11)

## Architecture

```
Arcp::Client            # session-oriented client
Arcp::Runtime::Runtime  # server-side runtime; accepts transports
Arcp::Runtime::JobContext # passed to agent handlers
Arcp::Session::*        # Hello, Welcome, CapabilitySet, Feature, AgentInventory, ...
Arcp::Job::*            # Submit, Accepted, Event, Result, JobError, Handle, Summary
Arcp::Job::EventKind    # 10 standard kinds
Arcp::Lease::*          # Lease, LeaseRequest, LeaseConstraints, CostBudget, Subsetting
Arcp::Transport::*      # MemoryTransport, WebSocketTransport, StdioTransport
Arcp::Auth::*           # AuthScheme, Bearer, Principal
Arcp::Errors::*         # 15 wire codes + 3 internal-only
Arcp::Trace             # Fiber-local Context, span helpers
```

## Transports

- `Arcp::Transport::MemoryTransport.pair` — in-process queue pair. Tests, embedded clients.
- `Arcp::Transport::WebSocketTransport` — wraps an `Async::WebSocket::Connection`. Production transport.
- `Arcp::Transport::StdioTransport` — newline-delimited JSON over a pair of IOs. Co-process agents.

## Deployment

Run the runtime as a daemon under the `socketry/async` reactor. Host
WebSocket endpoints with `falcon`. The runtime is fiber-based and
multiplexes sessions on the reactor; do not deploy under
request-per-thread servers like Puma.

## Errors

15 wire codes, each mapped to an `Arcp::Errors::*` subclass with a
`retryable?` default: `Cancelled`, `InvalidRequest`, `Unauthenticated`,
`PermissionDenied`, `JobNotFound`, `AgentNotAvailable`, `DuplicateKey`,
`RateLimited`, `Internal`, `HeartbeatLost`, `Backpressure`,
`ProtocolViolation`, `Timeout`, `ResumeWindowExpired`,
`LeaseSubsetViolation`, `AgentVersionNotAvailable`, `LeaseExpired`,
`BudgetExhausted`. Three additional codes are library-internal and never
appear on the wire (`UNNEGOTIATED_FEATURE`, plus the abstract
`Arcp::Error` base and the generic `Internal` fallback).

## Documentation

See `docs/` for guides, concepts, and reference. Start with
`docs/getting-started.md`.

## Conformance

Spec-to-code matrix in [CONFORMANCE.md](CONFORMANCE.md).

## Development

```
bundle install
bundle exec rake          # spec + rubocop + steep
bundle exec rake docs     # build doc tree
```

## License

Apache-2.0. See `LICENSE`.
