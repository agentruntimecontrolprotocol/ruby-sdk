---
title: Architecture
sdk: ruby
kind: reference
order: 1
spec_sections: [§5, §6, §7]
---

# Architecture

## Namespace map

```
Arcp
  Client                  # session-oriented client
  Envelope                # wire envelope (Data.define)
  Error / Errors::*       # 15 wire codes + 3 internal-only
  Trace::Context          # Fiber-local trace propagation
  MessageTypes            # frozen string constants for envelope.type
  Auth
    AuthScheme            # verify(token) -> Principal | nil
    Bearer                # static-token verifier
    Principal             # id, name, scopes
  Session
    CapabilitySet         # features, encodings, agents; intersect/2
    Feature               # constants for negotiated features
    AgentInventory        # name@version resolution
    Hello / Welcome / Bye / SessionError
    Ping / Pong / Ack / ListJobs / JobsResponse
    Info                  # post-welcome snapshot
  Job
    Submit / Accepted / Event / Result / JobError
    Cancel / Subscribe / Subscribed / Unsubscribe
    Handle                # client-side ergonomic wrapper
    Summary               # list_jobs row
    EventKind             # 10 standard kinds
    EventBody::*          # one Data.define per kind
  Lease
    Lease / LeaseRequest / LeaseConstraints
    CostBudget / BudgetCounter
    Subsetting.bound      # delegate-time bound check
  Runtime
    Runtime               # public server entry point
    SessionActor          # per-connection actor
    JobManager            # agent registry + dispatch
    JobContext            # passed to handlers
    LeaseManager          # lease + budget accounting
    SubscriptionManager   # cross-session observers
    EventLog              # in-memory replay window
  Transport
    Base / MemoryTransport / WebSocketTransport / StdioTransport
```

## Concurrency model

All I/O runs on `socketry/async` fibers. There are no threads in the hot
path. The runtime expects to be entered under a `Sync { }` or
`Async { }` block; calling `runtime.accept(transport)` blocks the
current fiber and runs a `SessionActor` until the transport closes.

The client uses one fiber for the reader loop and a second for the
heartbeat. Public client methods are fiber-safe; cross-fiber state is
guarded by a `Mutex` over the pending-request and stream tables.

Handler code (the lambda passed to `register_agent`) runs in its own
fiber under the runtime reactor. Handlers may call `Async::Task.sleep`,
issue HTTP requests, etc.; they MUST NOT block the reactor with
synchronous I/O.

## Event flow

```
client.submit_job(...)
  -> client sends job.submit envelope
  -> runtime SessionActor receives, hands to JobManager
  -> JobManager allocates job_id, builds Lease, spawns handler fiber
  -> SessionActor sends job.accepted with job_id + lease
  -> handler emits via JobContext (progress, log, ..., stream_result)
     each emit -> SubscriptionManager fan-out + EventLog append
  -> handler calls ctx.finish or ctx.fail!
  -> runtime sends job.result or job.error
  -> client.subscribe_job enumerator terminates
  -> client.get_result returns Result or raises mapped Errors::*
```

## Runtime + Client interaction

`Runtime` is process-wide and stateful: it owns the agent registry, the
event log, lease accounting, and the subscription table. `Client` is
per-connection and ephemeral: it owns a transport, a session snapshot,
and per-job stream queues.

The two never share memory across a real network. Same-process tests use
`MemoryTransport.pair` so a single Ruby process can host both.

## Capabilities

A session's `CapabilitySet` advertises `features`, `encodings`, and
(server-side) an `AgentInventory`. The handshake intersects client and
server sets; the result is stored on `client.session.capabilities`.

### Feature constants

```ruby
Arcp::Session::Feature::HEARTBEAT         # 'heartbeat'
Arcp::Session::Feature::ACK               # 'ack'
Arcp::Session::Feature::LIST_JOBS         # 'list_jobs'
Arcp::Session::Feature::SUBSCRIBE         # 'subscribe'
Arcp::Session::Feature::LEASE_EXPIRES_AT  # 'lease_expires_at'
Arcp::Session::Feature::COST_BUDGET       # 'cost.budget'
Arcp::Session::Feature::PROGRESS          # 'progress'
Arcp::Session::Feature::RESULT_CHUNK      # 'result_chunk'
Arcp::Session::Feature::AGENT_VERSIONS    # 'agent_versions'
```

`Arcp::Session::Feature::ALL` is a frozen Array of all eleven.

### Negotiation

```ruby
client_caps = Arcp::Session::CapabilitySet.local(
  features:  ['heartbeat', 'list_jobs'],
  encodings: ['utf8']
)
server_caps = Arcp::Session::CapabilitySet.local(
  features:  ['heartbeat', 'subscribe'],
  encodings: ['utf8', 'base64']
)

effective = client_caps.intersect(server_caps)
effective.features  # ['heartbeat']  -- intersection
effective.encodings # ['utf8']       -- intersection
```

`Arcp::Client.open` performs this intersection automatically.

### Checking a negotiated feature

```ruby
if client.session.supports?(Arcp::Session::Feature::SUBSCRIBE)
  client.subscribe_job(job_id: id, history: true, from_event_seq: 0)
end
```

Calling a feature method without the negotiated capability raises
`Arcp::Errors::UnnegotiatedFeature`.

## Agent versioning

Agents declare a fixed set of versions and one default. Clients submit
either by name (uses the default) or by `name@version` (pin).

```ruby
runtime.register_agent(
  name: 'code-refactor',
  versions: %w[1.0.0 2.0.0],
  default: '2.0.0',
  handler: ->(ctx) { ctx.finish(result: ctx.agent) }
)

client.submit_job(agent: 'code-refactor')        # resolves to 2.0.0
client.submit_job(agent: 'code-refactor@1.0.0')  # pins to 1.0.0
```

An unknown version raises `Arcp::Errors::AgentVersionNotAvailable` with
`details['available']` populated. `AgentInventory#resolve(ref)` can
validate a ref before submit:

```ruby
client.session.capabilities.agents.resolve('code-refactor@1.0.0')
# => 'code-refactor@1.0.0'
client.session.capabilities.agents.resolve('code-refactor@9.9.9')
# => nil
```

See [guides/agent-versioning.md](guides/agent-versioning.md) for the full
versioning guide.
