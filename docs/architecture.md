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
    EventLog              # replay window
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
