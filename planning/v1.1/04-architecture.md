# 04 — Architecture & Idioms

Decisions binding on every later phase. Inputs: `01-spec-delta.md`
(Feature constants, `CapabilitySet`, `AgentInventory` in §3 — referenced,
not duplicated), `02-current-audit.md` (target module map §4.3, v1.0
re-baseline list §6, deployment constraint §7), spec
`../spec/docs/draft-arcp-02.1.md` §5–§12.

## 1. Gem layout

### 1.1. One core gem: `arcp`

Single gem published as `arcp` (current `arcp.gemspec` at the repo root —
keep). `lib/arcp/` is the only load path; submodules sit under `Arcp::*`
per the target map in `02-current-audit.md` §4.3.

The TypeScript SDK ships `@arcp/{core,client,runtime,sdk}` (see
`../typescript-sdk/packages/`) because Node consumers pay a bundle-size
cost for unused subtrees. Ruby's `require` is lazy at the file level and
gems aren't tree-shaken, so a `arcp-core` / `arcp-client` / `arcp-runtime`
split would force users to write `gem 'arcp-core'; gem 'arcp-client'` in
their `Gemfile` for no payoff. `sidekiq`, `faraday`, `roda`, `sequel`,
`grape` — all single-gem libraries with optional `require` paths inside
(`sidekiq/web`, `faraday/retry`). That is the Ruby precedent. The
fan-out lives in `require 'arcp/client'` vs `require 'arcp/runtime'`,
not in gem boundaries. Verdict: **one gem**.

### 1.2. Two side gems carved out of `arcp`

Both are mechanical extractions per `02-current-audit.md` §6:

| Gem            | Extracted from                       | Reason                                                                                            | Hard dep removed from core |
| -------------- | ------------------------------------ | ------------------------------------------------------------------------------------------------- | -------------------------- |
| `arcp-cli`     | `lib/arcp/cli.rb` + `exe/arcp`       | CLI is operator-side; library users importing `arcp` for an SDK should not pull a CLI framework.   | `dry-cli ~> 1.0`           |
| `arcp-auth-jwt`| `lib/arcp/auth/jwt.rb`               | Spec §6.1 requires bearer; JWT verification is one of many bearer formats. A v1.1 client speaking to a runtime that hands out opaque tokens does not need `jwt`. | `jwt ~> 2.0`               |

Both depend on `arcp`; the `arcp` core gem does not know they exist.
`arcp-cli` ships `exe/arcp`, preserving the binary name.

### 1.3. Middleware adapter gems — Phase 05

`arcp-rack`, `arcp-falcon`, `arcp-rails`, `arcp-otel` — out of scope
for Phase 04. Their existence shapes Phase 04 only by forbidding
`Rack`, `falcon`, `rails`, `actioncable`, or `opentelemetry-sdk`
dependencies inside `arcp`'s gemspec. `opentelemetry-api` is permitted
in core (`02-current-audit.md` §2): it's a 0-dep type interface that the
consumer wires.

### 1.4. Flat namespace — no `Arcp::Core::`

TS: `@arcp/core` → namespace `core` inside imports. Ruby: a flat
`Arcp::Envelope`, `Arcp::Client`, `Arcp::Runtime`, `Arcp::Session`,
`Arcp::Job`, `Arcp::Lease`, `Arcp::Errors`, `Arcp::Transport`,
`Arcp::Trace`, `Arcp::Auth`. No `Arcp::Core::Envelope`. Reasons:

- Ruby modules are not packages. `Arcp::Core::Envelope` adds a path
  segment that carries no information — `Envelope` only ever lives in
  one namespace.
- `02-current-audit.md` §4.3 already targets flat names.
- `STYLE.md` `Style/ClassAndModuleChildren: nested` makes the deeper
  nesting visually noisy across every file's `module Arcp; module
  Core; module ...; end; end; end` open block.

Map: `@arcp/core` → `Arcp::{Envelope, Session, Job, Lease, Errors,
Transport, Trace}`. `@arcp/client` → `Arcp::Client`. `@arcp/runtime` →
`Arcp::Runtime` (and submodules `Arcp::Runtime::JobManager`,
`Arcp::Runtime::LeaseManager`, `Arcp::Runtime::SubscriptionManager`,
`Arcp::Runtime::EventLog`). `@arcp/sdk` is the umbrella TS facade —
in Ruby that's just `require 'arcp'`, which `require`s the rest.

## 2. Type model

### 2.1. `Data.define` everywhere

Every envelope, every payload, every value object: `Data.define(...)`.
Already the idiom: `lib/arcp/envelope.rb:16` defines `Envelope` as
`Data.define`; `lib/arcp/messages/base.rb` is the factory
(`Arcp::Messages.define`); `lib/arcp/messages/session.rb` shows the
shape. Phase 04 keeps the idiom and tightens it:

- Frozen by construction (`Data` instances are deep-frozen at the
  reference level — keep arrays and hashes inside frozen too).
- Keyword-constructable (`Data.define(:a, :b).new(a:, b:)`).
- Value-comparable (`==` compares fields).
- Pattern-matchable (`case env in Envelope(type: 'job.event',
  payload:)`).

The current `Envelope` carries 19 fields. The v1.0 re-baseline
(`02-current-audit.md` §6.1) cuts it to 8: `arcp`, `id`, `type`,
`session_id`, `trace_id`, `job_id`, `event_seq`, `payload`. That is a
Phase 10 milestone; Phase 04 only commits to the target shape.

### 2.2. Discriminator: closed `case ... in` over `MESSAGE_TYPES`

The current registry (`lib/arcp/message_type.rb`) is a runtime
`Hash[String → Class]` guarded by a `Mutex`. It works for v1.0
because the wire type set is open-ended (RFC-0001 had 58 literals per
`02-current-audit.md` §4.2). v1.0/v1.1 collapses that to ~16 envelope
types (`02-current-audit.md` §6.5: events unify under `job.event`).
That's a **closed set**, and a closed set wants a closed dispatch.

Decision: **replace the runtime registry with a `MESSAGE_TYPES`
constants module + `case ... in` dispatch**. One string constant per
spec §6–§8 envelope type. The dispatcher is a frozen module-level
constant, not a mutable Hash. Sketch:

```
module Arcp::MessageTypes
  SESSION_HELLO      = 'session.hello'
  SESSION_WELCOME    = 'session.welcome'
  SESSION_BYE        = 'session.bye'
  SESSION_ERROR      = 'session.error'
  SESSION_PING       = 'session.ping'
  SESSION_PONG       = 'session.pong'
  SESSION_ACK        = 'session.ack'
  SESSION_LIST_JOBS  = 'session.list_jobs'
  SESSION_JOBS       = 'session.jobs'
  JOB_SUBMIT         = 'job.submit'
  JOB_ACCEPTED       = 'job.accepted'
  JOB_EVENT          = 'job.event'
  JOB_RESULT         = 'job.result'
  JOB_ERROR          = 'job.error'
  JOB_CANCEL         = 'job.cancel'
  JOB_SUBSCRIBE      = 'job.subscribe'
  JOB_SUBSCRIBED     = 'job.subscribed'
  JOB_UNSUBSCRIBE    = 'job.unsubscribe'

  ALL = [...].freeze
end
```

Justification for closing it:

- **Exhaustiveness.** `case env.type in SESSION_HELLO | SESSION_WELCOME
  | ...` makes a missing arm a `NoMatchingPatternError` at decode
  time, not silent passthrough. A `Hash` lookup returning `nil` had no
  such guarantee; `lib/arcp/message_type.rb#class_for` returns `nil`
  for unknowns, pushing the burden onto every caller.
- **Forward compat.** Unknown wire types (e.g. a v1.2 `job.pause`)
  still need to be handled: the dispatcher has an `else` arm that
  decodes into an opaque `Arcp::UnknownEnvelope` value (frozen, raw
  payload Hash). Phase 01 §4 explicitly bans pre-baking hooks for
  unreleased features; the `else` arm satisfies forward-compat without
  pre-baking type-specific code.
- **No vendor extensions.** The current `MessageTypeRegistry#core?`
  excludes `x-` prefixes and namespaced names from "core." Vendor
  extensions stay on the wire as raw envelopes with `type:
  'vendor.x.foo'`; they hit the `else` arm and surface as
  `UnknownEnvelope`. A v1.1 client never dispatches into vendor code,
  so the registry's vendor-friendly indirection is unused.
- **Performance is incidental.** A `case ... in` over string literals
  YJIT-compiles to direct comparisons; the `Mutex#synchronize` in
  `MessageTypeRegistry.class_for` is gone. Not the reason — the
  reason is exhaustiveness.

What's retired: the `MessageTypeRegistry` module itself, its `register`
hook, its `known` introspection. Anything that needs the wire-string
table reads `Arcp::MessageTypes::ALL`.

### 2.3. Worked example — `job.event { kind, body }`

`job.event` is one envelope; `kind` is the spec's discriminator for
the body (§8.2). Ruby has no sum types — `case ... in` over a closed
constants module is the convention that approximates one. Phase 06
samples will use this shape.

```
module Arcp::Job::EventKind
  PROGRESS     = 'progress'
  RESULT_CHUNK = 'result_chunk'
  LOG          = 'log'
  THOUGHT      = 'thought'
  TOOL_CALL    = 'tool_call'
  TOOL_RESULT  = 'tool_result'
  STATUS       = 'status'
  METRIC       = 'metric'
  TRACE_SPAN   = 'trace_span'
  DELEGATE     = 'delegate'
end

module Arcp::Job
  Event = Data.define(:job_id, :event_seq, :kind, :body)

  module Event::Progress
    Body = Data.define(:current, :total, :units, :message)
  end

  module Event::ResultChunk
    Body = Data.define(:result_id, :chunk_seq, :data, :encoding, :more)
  end
  # ... one Body per kind ...
end
```

Dispatch:

```
case event.body
in Arcp::Job::Event::Progress::Body(current:, total:)
  on_progress(current, total)
in Arcp::Job::Event::ResultChunk::Body(result_id:, chunk_seq:, data:, more:)
  on_chunk(result_id, chunk_seq, data, more)
in Arcp::Job::Event::ToolResult::Body(call_id:, result:)
  on_tool_result(call_id, result)
# ...
end
```

"Sealed by convention": the constants in `EventKind::*` are the only
values the decoder builds Body instances for; an unknown `kind`
decodes into `Event` with `body` set to the raw payload Hash and is
surfaced (not raised) so a v1.1 client tolerates a v1.2 runtime
emitting `kind: 'profiling'`. Phase 07 owns a test that asserts the
match block has one arm per `EventKind::*` constant.

## 3. Concurrency model

### 3.1. `socketry/async`, Fiber scheduler, no threads in I/O paths

Confirmed in Phase 03 (`03-libraries.md` — not yet written, but the
audit §2 already keeps `async ~> 2.0` and `async-websocket ~> 0.30`).
Every I/O boundary opens an `Async { ... }` block; every recv loop is
a Fiber under `Async::Reactor`. The runtime is hosted by Falcon or a
daemon (`02-current-audit.md` §7). No `puma`-per-request worker.

`Sync { ... }` (also socketry) is the synchronous entry point — Phase
07 tests use `Sync { client.open(...) }` to drive an `Async` API from a
RSpec `it` block without spinning a reactor manually.

### 3.2. Cancellation: `Async::Task#stop` → `Async::Stop` propagation

Cancellation is **not** a custom signal. It's `task.stop`, which raises
`Async::Stop` inside the task at its next suspension point. Every
`Async` block in the SDK that owns a resource (a WebSocket, a SQLite
cursor, an `Async::Queue` reader) wraps the body in `begin ... ensure
... end`. Rescue-clauses are wrong here because `Async::Stop` should
propagate; `ensure` closes the resource and the task dies. The Phase
01 §3 mention of `lib/arcp/runtime/lease_manager.rb` cancellation
hooks lives under this rule.

`02-current-audit.md` §5 row §6.6 calls out the SQLite cursor leak risk
on `Async::Stop`: `lib/arcp/store/event_log.rb` opens a prepared
statement for cursored pagination; the `ensure` block must `#close`
it. Phase 07 §5.3 tests this.

### 3.3. Streams: `Enumerator::Lazy` backed by `Async::Queue#each`

Two surface idioms:

- **Bounded sequences** (`Client#list_jobs` paginates until
  `next_cursor == nil`): `Enumerator::Lazy` so the consumer can
  `.first(50)`, `.take_while`, or `break`-out. Internally implemented
  as `Enumerator.new` yielding pages, then `.lazy`.
- **Unbounded sequences** (`Client#subscribe_job`,
  `Client#result_chunks`): an `Async::Queue` is the producer side; the
  consumer reads with `queue.each` (or `queue.dequeue` in a loop).
  Exposed publicly as `Async::Queue#each` — the consumer gets the
  `Async`-aware iteration. Closing the upstream pushes a sentinel
  (`queue.close`) that ends the iteration.

Hard rule: **never raw `Array` for unbounded sequences.** A client
reading 10 GB of `result_chunk` data into an Array is a leak; the
`Enumerator::Lazy` / `Async::Queue#each` rule is what prevents it.

### 3.4. Suspension-point hygiene for §9.6 cost budgets

Spec §9.6 requires per-currency counters checked before every
authority op. `BigDecimal` arithmetic on a `Hash[String → BigDecimal]`
is the storage. Fibers are cooperative on one thread, so a
read-modify-write sequence is **safe iff no suspension happens between
the read and the write**.

Rule, stated formally:

> Between `Arcp::Lease::CostBudget#remaining(ccy)` and
> `Arcp::Lease::CostBudget#decrement(ccy, amount)`, no `Async::Task`
> may suspend. Specifically: no `await`, no `#wait`, no
> `Fiber.scheduler.io_wait`, no `Async::Queue#dequeue`, no
> `sleep`, no `Async::Task.yield`.

If a check requires I/O (e.g. a remote ledger lookup), the I/O happens
**before** the read-modify-write, and the result is captured into a
local variable that the RMW closes over. The RMW itself is three
non-suspending lines. Phase 07 owns a test that injects a fiber yield
between read and decrement and asserts it raises a defect — the
production code path must not exercise that branch.

### 3.5. Heartbeat / ack timers (§6.4 / §6.5)

One `Async::Task` per session for the heartbeat. Owned by the
`Arcp::Session` value object's containing object (the `Client` or the
`Runtime::Session` actor — Phase 04 places it on the latter). Closing
the session **must** `task.stop` the timer; a leaked timer fiber holds
a reference to the `Async::Queue` for outgoing sends and prevents GC
of the transport. `02-current-audit.md` §5 row §6.4 names this risk.

Ack emission is rate-limited inside the same fiber that consumes
inbound events — "at most per event or per few-hundred ms, whichever
is less frequent" per `01-spec-delta.md` §1 row §6.5. Implemented as a
small state machine `{last_ack_seq, last_ack_emitted_at}` checked at
each inbound event. No timer fiber.

## 4. Error model

### 4.1. Base unchanged

`Arcp::Error < StandardError`, file `lib/arcp/error.rb`. Keep the
shape: `#code`, `#retryable?`, `#details`, `#to_payload(trace_id:)`.

The current file defines `#code` to return `ErrorCode::UNKNOWN`;
subclasses override with an endless `def code = ErrorCode::CANCELLED`.
Phase 04 keeps that pattern.

### 4.2. The 15-code v1.1 set

12 v1.0 codes + 3 v1.1 codes from `01-spec-delta.md` §2. Each gets one
`Arcp::Errors::*` subclass (note the namespace flip: current code
nests the subclasses inside `Arcp::Error`; the target per
`02-current-audit.md` §4.3 is `Arcp::Errors::*` — `Errors` plural,
sibling of `Error`).

| # | Spec code (v1.0)        | Ruby class                              | `retryable?` default |
| - | ----------------------- | --------------------------------------- | -------------------- |
| 1 | `CANCELLED`             | `Arcp::Errors::Cancelled`               | false                |
| 2 | `INVALID_REQUEST`       | `Arcp::Errors::InvalidRequest`          | false                |
| 3 | `UNAUTHENTICATED`       | `Arcp::Errors::Unauthenticated`         | false                |
| 4 | `PERMISSION_DENIED`     | `Arcp::Errors::PermissionDenied`        | false                |
| 5 | `JOB_NOT_FOUND`         | `Arcp::Errors::JobNotFound`             | false                |
| 6 | `AGENT_NOT_AVAILABLE`   | `Arcp::Errors::AgentNotAvailable`       | true                 |
| 7 | `DUPLICATE_KEY`         | `Arcp::Errors::DuplicateKey`            | false                |
| 8 | `RATE_LIMITED`          | `Arcp::Errors::RateLimited`             | true                 |
| 9 | `INTERNAL`              | `Arcp::Errors::Internal`                | true                 |
| 10| `HEARTBEAT_LOST`        | `Arcp::Errors::HeartbeatLost`           | true                 |
| 11| `BACKPRESSURE`          | `Arcp::Errors::Backpressure`            | true                 |
| 12| `PROTOCOL_VIOLATION`    | `Arcp::Errors::ProtocolViolation`       | false                |
| 13| **`AGENT_VERSION_NOT_AVAILABLE`** (v1.1, §12) | `Arcp::Errors::AgentVersionNotAvailable` | **false** |
| 14| **`LEASE_EXPIRED`** (v1.1, §12)               | `Arcp::Errors::LeaseExpired`             | **false** |
| 15| **`BUDGET_EXHAUSTED`** (v1.1, §12)            | `Arcp::Errors::BudgetExhausted`          | **false** |

Each subclass:

```
module Arcp::Errors
  class LeaseExpired < Arcp::Error
    CODE = 'LEASE_EXPIRED'

    def initialize(message: nil, details: {})
      @details = details.freeze
      super(message || "lease expired (#{details[:lease_id]})")
    end

    def code = CODE
    def retryable? = false
    def details = @details
  end
end
```

`CODE` is a constant on each subclass — the base reads
`self.class::CODE` if a subclass forgets to override `#code`, but each
subclass overrides explicitly for grep-ability. `details:` is a
frozen Hash, kw-arg constructed. `retryable?` is overridden to return
`false` for the three new codes per spec §12 (`retryable: false`
fixed); for the v1.0 codes, the retryable defaults match the table
above and Phase 07 asserts each one.

### 4.3. `Arcp::ErrorCode` retirement

`lib/arcp/error_code.rb` currently ships 21 gRPC-style codes
(`02-current-audit.md` §1 row §12 lists them). The v1.0 re-baseline
(§6.6) cuts this to 15. Retired strings:

`OK`, `UNKNOWN`, `INVALID_ARGUMENT` (→ `INVALID_REQUEST`),
`DEADLINE_EXCEEDED`, `NOT_FOUND` (→ `JOB_NOT_FOUND`), `ALREADY_EXISTS`
(→ `DUPLICATE_KEY`), `RESOURCE_EXHAUSTED` (→ `RATE_LIMITED`),
`FAILED_PRECONDITION`, `ABORTED`, `OUT_OF_RANGE`, `UNIMPLEMENTED`,
`UNAVAILABLE`, `DATA_LOSS`, `LEASE_REVOKED`, `BACKPRESSURE_OVERFLOW`
(→ `BACKPRESSURE`).

Six codes rename; nine delete outright. Phase 10 schedules this as
part of milestone 1 (v1.0 re-baseline). Phase 04 commits to the
15-entry shape and the `Arcp::Errors::*` flat layout.

`Arcp::Errors::ErrorCode` remains as a constants module (15 string
constants) for places that need the wire string without raising. The
`RETRYABLE_BY_DEFAULT` / `NON_RETRYABLE_BY_DEFAULT` sets get re-keyed
to the 15-code set; Phase 07 owns the test that asserts every code
appears in exactly one set.

## 5. Public API sketch — top types

Signatures only (no bodies). Keyword arguments at every 3+-arg public
seam. RBS sigs land at the same seams in Phase 03's tool (RBS + steep
per the bootstrap candidate list).

### 5.1. `Arcp::Client`

```
module Arcp
  class Client
    def self.open(url:, auth:, capabilities: nil, on_event: nil) end

    def list_jobs(status: nil, agent: nil, created_after: nil, cursor: nil) end
    def submit_job(agent:, input:, lease_request: nil, lease_constraints: nil,
                   idempotency_key: nil, max_runtime_sec: nil) end
    def subscribe_job(job_id:, from_event_seq: nil, history: false) end
    def cancel_job(job_id:, reason: nil) end
    def get_result(job_id:) end
    def close(reason: nil) end

    attr_reader :session  # Arcp::Session, immutable post-welcome
  end
end
```

`list_jobs` returns `Enumerator::Lazy[Arcp::Job::Summary]` paging on
`next_cursor` (§6.6). `subscribe_job` returns
`Async::Queue#each`-backed `Enumerator` of `Arcp::Job::Event` (§7.6).
`submit_job` returns `Arcp::Job::Handle`. `get_result` returns
`Arcp::Job::Result` or, when chunked, `Enumerator::Lazy[String]`
decoding `result_chunk` events (§8.4).

### 5.2. `Arcp::Runtime`

```
module Arcp
  class Runtime
    def initialize(transport:, auth_verifier:, agents:, event_log: nil,
                   heartbeat_interval_sec: 30, capabilities: nil) end

    def serve_async end
    def register_agent(name:, versions:, default:, handler:) end
    def shutdown(reason: nil) end

    attr_reader :capabilities
  end
end
```

`serve_async` returns an `Async::Task`; cancellation is `task.stop`.
`register_agent` mutates the runtime's agent table — the only
mutable manager surface, guarded by a `Mutex#synchronize` block per
the hard rule in §6 below.

### 5.3. `Arcp::Transport` interface

```
module Arcp
  module Transport
    # Abstract. Implementations: MemoryTransport, WebSocketTransport,
    # StdioTransport.
    class Base
      def send(envelope) end                # Arcp::Envelope -> nil
      def receive end                        # blocks under Async; -> Envelope
      def close(reason: nil) end             # -> nil; idempotent
    end
  end
end
```

`receive` suspends the calling fiber until an envelope arrives or the
transport closes (raises `Arcp::Errors::Cancelled`). Phase 05 owns
where the WS upgrade attaches.

### 5.4. `Arcp::Session` — immutable post-welcome

```
module Arcp
  Session = Data.define(:id, :runtime_version, :capabilities, :agents,
                        :heartbeat_interval_sec, :resume_token)
end
```

`capabilities` is `Arcp::Session::CapabilitySet` (per
`01-spec-delta.md` §3.2 — sketched there, defined under `Arcp::Session`
the module). `agents` is `Arcp::Session::AgentInventory`. Once the
welcome lands, the `Session` `Data` is frozen for the connection's
lifetime; resume creates a new `Session` value.

### 5.5. `Arcp::Job::Handle`, `Arcp::Job::Summary`

```
module Arcp::Job
  Handle = Data.define(:job_id, :agent, :submitted_at, :lease) do
    def subscribe(client:, **kw) = client.subscribe_job(job_id:, **kw)
    def cancel(client:, reason: nil) = client.cancel_job(job_id:, reason:)
  end

  Summary = Data.define(:job_id, :agent, :status, :created_at,
                        :lease_expires_at, :budget_remaining)
end
```

`Handle` is what `submit_job` returns; `Summary` is what `list_jobs`
yields (one per row from the cursored response).

### 5.6. `Arcp::Lease::Lease`

```
module Arcp::Lease
  LeaseRequest      = Data.define(:capabilities, :budget, :expires_at)
  LeaseConstraints  = Data.define(:expires_at, :max_budget)  # §9.5/§9.6
  CostBudget        = Data.define(:per_currency)             # §9.6
  Lease             = Data.define(:id, :capabilities, :budget,
                                  :expires_at, :issued_at)
end
```

`CostBudget#per_currency` is a frozen `Hash[String, BigDecimal]` —
`BigDecimal` per the §9.6 decimal-math requirement. The
`CostBudget#decrement` / `#remaining` pair lives on a separate
mutable counter object (`Arcp::Runtime::BudgetCounter`), not on this
frozen value — see §3.4 for the suspension-point rule.

## 6. Hard rules recap

Carried from `STYLE.md`, `.rubocop.yml`, and the BOOTSTRAP anti-slop
list:

1. **`# frozen_string_literal: true` on every `.rb` file.** Enforced
   by `.rubocop.yml:32–33` (`Style/FrozenStringLiteralComment`
   `Enabled: true, EnforcedStyle: always` per `02-current-audit.md`
   §3). Keep. New code in Phase 04+ inherits this.

2. **No monkey patches on `String`, `Hash`, `Array`, `Integer`,
   `Time`, `Object`, `Kernel`, etc.** The `Arcp::Json` module
   (`lib/arcp/json.rb` — to be renamed `Arcp::Serializer` per
   `02-current-audit.md` §4.3) uses module functions, not core
   extensions.

3. **No `extend self` modules that hide mutable state.** A module
   with class-level state lookalikes (e.g. the current
   `MessageTypeRegistry`'s `@types` + `@mutex` at lines 12–13) is
   either a real class or a frozen constants module. The decision
   in §2.2 retires that exact pattern.

4. **No `method_missing` on the public surface.** Internal DSLs (if
   any — Phase 04 does not introduce one) may use `method_missing`,
   but no class anyone consumes from `gem 'arcp'` does. `Data.define`
   doesn't use `method_missing` — it generates real methods. Keep.

5. **No `attr_accessor` on a public class.** `Data.define` covers
   value objects; `attr_reader` covers read-only fields on classes
   (the current `Arcp::Error::PermissionDenied` uses `attr_reader
   :permission, :resource` at `lib/arcp/error.rb:71` — fine).
   Mutation is allowed only inside a `Mutex#synchronize` on classes
   that explicitly document mutability in their YARD comment.

6. **Keyword arguments at every public 3+-arg seam.** All §5
   signatures comply. The exception: 2-arg methods may use
   positional args (`Transport#send(envelope)`).

7. **`Enumerator::Lazy` or `Async::Queue#each` for streams.** Never
   a raw `Array` for an unbounded sequence — §3.3 spelled this out.

8. **RBS sigs at the public seam.** Phase 03 picks RBS + steep vs
   Sorbet; Phase 04 commits to: sigs land for `Arcp::Client`,
   `Arcp::Runtime`, `Arcp::Transport::Base`, `Arcp::Session`,
   `Arcp::Job::Handle`, `Arcp::Lease::*`, and every
   `Arcp::Errors::*` subclass. The 14 message-payload `Data.define`s
   under `Arcp::Session::*` and `Arcp::Job::*` get sigs too —
   `Data` works with RBS via `interface _Each` … no special handling.
   Internal manager classes (`JobManager`, `LeaseManager`,
   `SubscriptionManager`) sigs are deferred to Phase 08.

9. **No `Rails`-coupled deps in core.** Reaffirmed from
   `02-current-audit.md` §2. `arcp-rails` lives in Phase 05.

10. **One `MESSAGE_TYPES` constants module.** No second source of
    truth. `Arcp::MessageTypes::ALL.freeze` is the one list.

## 7. Hand-off

| Phase | Phase 04 commits                                                                                                        |
| ----- | ----------------------------------------------------------------------------------------------------------------------- |
| 05    | Middleware adapters dep on `arcp` only; `arcp-rack` and `arcp-falcon` consume `Arcp::Runtime` and `Arcp::Transport::Base`. |
| 06    | Sample files use `Async { ... }` / `Sync { ... }` blocks, `case ... in` for dispatch, `Data.define` for payloads.        |
| 07    | Tests assert: exhaustive arm coverage for `MESSAGE_TYPES` and `EventKind`; `Async::Stop` propagation; suspension-point hygiene rule (§3.4); 15-code error set. |
| 08    | RBS sigs at the public seams listed in §6 rule 8; YARD comments on every public method.                                  |
| 09    | Module dep graph reads from §1.4 flat namespace; session FSM reads from §3.5 timers and `Arcp::Session` immutable shape.   |
| 10    | Schedule v1.0 re-baseline ahead of v1.1 features; the 15-code retirement (§4.3) and registry retirement (§2.2) ride along. |
