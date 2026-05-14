# 06 — Examples

Sources read: `../typescript-sdk/examples/README.md` (the 18-row
canonical list — host-integration rows excluded as scope-out, see §1),
`../spec/docs/draft-arcp-02.1.md`, `01-spec-delta.md`, `02-current-audit.md`.
Phase 04 (`04-architecture.md`) has not been written at the time of this
plan; type-shape citations point at the `Data.define` sketches already
fixed in `01-spec-delta.md` §3.1–§3.3 and the target module tree in
`02-current-audit.md` §4.3.

Each example is a directory under `samples/<name>/` with exactly three
files: `server.rb`, `client.rb`, `run.rb`. No shared fixtures, no
`README.md` per sample (the table below is the doc). The 14 current
sample directories in `samples/` (`02-current-audit.md` §6 + §9) are
RFC-0001-keyed and are deleted wholesale before this tree is written.

## 1. Mapping table — 18 examples

**Scope-out:** the four TS host-integration examples (`tracing/`,
`express/`, `fastify/`, `bun/`) are not under `samples/` — they belong
with the middleware gems (`arcp-otel`, `arcp-rack`, `arcp-falcon`,
`arcp-rails`) planned in `05-middleware.md` and will land as
runnable READMEs inside each adapter gem. They are not in the table
below; the row count is 9 v1.0 core + 9 v1.1 features = 18.

| #  | TS name             | Ruby sample path              | Files                                | Spec §        | Ruby idiom shown                                                                                                                                                                                                  |
| -- | ------------------- | ----------------------------- | ------------------------------------ | ------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
|  1 | `submit-and-stream` | `samples/submit_and_stream/`  | `server.rb`, `client.rb`, `run.rb`   | §13.1, §7.1, §8.2 | Client consumes `Arcp::Client#submit(...).events` as an `Enumerator::Lazy` of `Arcp::Job::Event` `Data` values; dispatch via `case event in {kind: 'log', body: {message:}}` pattern matching across the 7 reserved kinds. |
|  2 | `delegate`          | `samples/delegate/`           | `server.rb`, `client.rb`, `run.rb`   | §13.2, §10    | Parent runtime emits a `kind: 'delegate'` body; child job inherits `trace_id` from `Arcp::Trace.current` (fiber-local). Child lease assembled via `Arcp::Lease::LeaseSubsetting.bound(parent:, request:)`.            |
|  3 | `resume`            | `samples/resume/`             | `server.rb`, `client.rb`, `run.rb`   | §13.3, §6.3   | Client `.disconnect!` mid-stream, then `Client.resume(resume_token:, last_event_seq:)`; replay drains the `Async::Queue` before live events arrive. A fresh `resume_token` is read from the new `Welcome`.            |
|  4 | `idempotent-retry`  | `samples/idempotent_retry/`   | `server.rb`, `client.rb`, `run.rb`   | §13.5, §7.2   | Same `(principal, idempotency_key)` returns the same `job_id`; same key + different agent raises `Arcp::Errors::DuplicateKey` (Phase 01 §2). Asserted via `expect { ... }.to raise_error`-style guard in `run.rb`.    |
|  5 | `lease-violation`   | `samples/lease_violation/`    | `server.rb`, `client.rb`, `run.rb`   | §13.4, §9.3   | Agent's `tool.call` outside lease surfaces as a `tool_result` event whose body carries `error.code == 'PERMISSION_DENIED'`; job continues and terminates `success`. No exception is raised on the client.            |
|  6 | `cancel`            | `samples/cancel/`             | `server.rb`, `client.rb`, `run.rb`   | §7.4          | Client submits, sends `job.cancel`, and the agent's `Async::Task` receives `Async::Stop` via `task.stop`. Runtime emits `job.error { final_status: 'cancelled' }`. **No `sleep`** — `with_timeout` (harness §3) drives. |
|  7 | `stdio`             | `samples/stdio/`              | `server.rb`, `client.rb`, `run.rb`   | §4.2          | `run.rb` spawns `ruby server.rb` as a child via `Process.spawn` and wires `IO.pipe` pairs into `Arcp::Transport::StdioTransport`; single-process run (no second terminal). Exit-on-EOF semantics asserted.            |
|  8 | `vendor-extensions` | `samples/vendor_extensions/`  | `server.rb`, `client.rb`, `run.rb`   | §8.2, §9.2, §15 | Agent emits `kind: 'x-vendor.acme.progress'`; client demonstrates both the naïve `else: # ignore` branch and a `case ... in {kind: /\Ax-vendor\.acme\./}` aware branch. Lease namespace `x-vendor.acme.metrics` likewise. |
|  9 | `custom-auth`       | `samples/custom_auth/`        | `server.rb`, `client.rb`, `run.rb`   | §6.1          | Replaces the bundled `Arcp::Auth::BearerAuth` with an HMAC-signed token verifier — a class with `#verify(token) -> Principal \| nil`. Bad tokens are refused at `session.hello` with `Arcp::Errors::Unauthenticated`. |
| 10 | `heartbeat`         | `samples/heartbeat/`          | `server.rb`, `client.rb`, `run.rb`   | §6.4          | Client suppresses outbound traffic for 2× the negotiated `heartbeat_interval_sec` (driven by harness `fake_clock`); runtime closes the transport and the client surfaces `Arcp::Errors::HeartbeatLost`.               |
| 11 | `ack-backpressure`  | `samples/ack_backpressure/`   | `server.rb`, `client.rb`, `run.rb`   | §6.5, §8.2    | Client sends `session.ack { last_processed_seq: N }`; server's `Arcp::Runtime::EventLog` (per `02-current-audit.md` §5 row §6.5) frees buffered events ≤ N earlier than the time-based window; runtime emits a `status { phase: 'back_pressure' }` event when lag crosses threshold. |
| 12 | `list-jobs`         | `samples/list_jobs/`          | `server.rb`, `client.rb`, `run.rb`   | §6.6          | `Client#list_jobs(filter: {status: %w[running pending]}, limit: 2)` returns an `Enumerator::Lazy` that pages on `next_cursor`; consumed with `.first(5)`. Cursor is opaque to the client.                              |
| 13 | `subscribe`         | `samples/subscribe/`          | `server.rb`, `client.rb`, `run.rb`   | §7.6          | A second `Arcp::Client` (same principal, new session) calls `client.subscribe(job_id:, from_event_seq: 0, history: true)`; the returned `Async::Queue#each` replays buffered history then tails live. Subscriber's `job.cancel` is refused with `Arcp::Errors::PermissionDenied`. |
| 14 | `agent-versions`    | `samples/agent_versions/`     | `server.rb`, `client.rb`, `run.rb`   | §7.5          | `Client#submit(agent: 'code-refactor@1.0.0', ...)` resolves; `agent: 'code-refactor@3.0.0'` raises `Arcp::Errors::AgentVersionNotAvailable` (Phase 01 §2). `session.welcome.capabilities.agents` decoded into `Arcp::Session::AgentInventory` (Phase 01 §3.3). |
| 15 | `lease-expires-at`  | `samples/lease_expires_at/`   | `server.rb`, `client.rb`, `run.rb`   | §9.5          | Submit with `lease_constraints: {expires_at: clock.now + 60}`; harness `fake_clock` advances past the deadline mid-job; the next authority op surfaces a `tool_result` carrying `LEASE_EXPIRED`, then runtime emits `job.error { code: 'LEASE_EXPIRED' }`. Time comparison uses `Process.clock_gettime(Process::CLOCK_MONOTONIC)` per `02-current-audit.md` §5 row §9.5. |
| 16 | `cost-budget`       | `samples/cost_budget/`        | `server.rb`, `client.rb`, `run.rb`   | §9.6          | Agent emits `metric { name: 'cost.search', value: '0.42', unit: 'USD' }`; runtime decrements via `BigDecimal('0.42')` (Phase 01 §1 row §9.6, `02-current-audit.md` §2 explicit `bigdecimal` dep). Final tool call returns `tool_result` with `BUDGET_EXHAUSTED`. |
| 17 | `progress`          | `samples/progress/`           | `server.rb`, `client.rb`, `run.rb`   | §8.2.1        | Agent emits `kind: 'progress' { current:, total:, units: 'files' }`; client renders a running `current/total` line to `$stderr` via `StderrLogger` (harness §3). Advisory only — no protocol action.                  |
| 18 | `result-chunk`      | `samples/result_chunk/`       | `server.rb`, `client.rb`, `run.rb`   | §8.4          | Agent emits ~30 `result_chunk` events sharing one `result_id`; terminating `job.result` carries the same `result_id` + `result_size`. Client assembles via `handle.result_chunks.lazy.map { decode(_1) }.to_a.join` — an `Enumerator::Lazy` decoded per `encoding` (`utf8` or `base64`). |

### 1.1. TS examples that don't replicate verbatim in Ruby

- **`stdio` (row 7):** TS runs `pnpm tsx examples/stdio/client.ts` —
  a single command where the client spawns its own runtime. Ruby
  equivalent has `run.rb` doing the `Process.spawn` + `IO.pipe`
  plumbing rather than `client.rb` doing it, because Ruby's idiomatic
  child-process pattern lives outside the client class; `client.rb`
  stays transport-agnostic. The demonstration is identical.
- **`vendor-extensions` (row 8):** TS uses TypeScript's structural
  types to render the custom kind without declaring it. Ruby's
  equivalent is `case event in {kind: String => k}` with a regex
  guard on the `k` binding inside the arm — same demonstration,
  different mechanism. The body is decoded as a raw `Hash` (frozen)
  rather than into a typed `Data` value, because the kind is unknown
  to `Arcp::Job::Event::Kind`.

No TS example is dropped.

## 2. Runner shape

`ruby samples/<name>/run.rb` is the entry point. Exit code 0 on
success, non-zero on assertion failure. `run.rb` uses
`Arcp::Transport::MemoryTransport.pair` (see `02-current-audit.md` §4.1
row `Arcp::Transport::MemoryTransport`) for self-contained runs;
exceptions are the `stdio` row (uses `StdioTransport` via
`Process.spawn`) and any future `websocket` row (would use Falcon as
loopback, per `02-current-audit.md` §7 — not in the 18). Each sample
prints **one** terse summary line to `$stderr` (via the harness'
`StderrLogger`) and a **single** JSON line to `$stdout` containing the
sample's outcomes (`{"sample": "...", "ok": true, "asserts": {...}}`);
CI consumes the JSON via `jq -e '.ok'` to assert success and `jq
'.asserts'` for richer post-mortems. Cancellation samples (`cancel`,
`heartbeat`) call `task.stop` from outside the `Async::Task` body —
**no `Kernel#sleep`**. Time-based scenarios (`heartbeat`,
`lease-expires-at`) thread a `FakeClock` through `Arcp::Runtime` and
advance it explicitly inside `Async { }`; the `FakeClock` is itself a
Phase 04 (`04-architecture.md`) deliverable consumed by Phase 07 tests
and these two samples — both samples must `require_relative '_harness'`
before they can run.

## 3. Common harness

A single file `samples/_harness.rb` is `require_relative`'d by every
`run.rb`. It pulls **no gems** outside the runtime block of
`arcp.gemspec` (`02-current-audit.md` §2): `async`, `logger`, plus
`arcp` itself. The harness exposes:

- `Harness.run_or_exit { |emit| ... }` — wraps the body in
  `Sync { }` (top-level synchronous-scope entry into the `Async`
  reactor, idiomatic for one-shot scripts per the `async` gem README);
  catches every `StandardError` and `Async::Stop`, writes
  `{"sample": ..., "ok": false, "error": {...}}` JSON to `$stdout`,
  logs the backtrace to `$stderr`, and `exit(1)`s. On success it
  ensures the emit block was called exactly once.
- `Harness::StderrLogger` — a stdlib `Logger.new($stderr,
  level: Logger::INFO, formatter: ->(sev, _, _, msg) { "[#{sev}]
  #{msg}\n" })`. One concrete instance shared across `server.rb` and
  `client.rb` per sample.
- `Harness.emit(sample, asserts:)` — JSON-encodes
  `{sample:, ok: true, asserts:}` (via stdlib `json`, per Phase 03's
  default) and writes one line to `$stdout`. Idempotent — calling it
  twice in one run is an assertion failure.
- `Harness.with_timeout(seconds, task:) { |timer| ... }` — registers
  a `Async::Task` that calls `task.stop` after `seconds` of reactor
  time. Uses the reactor's own scheduler, not `Thread.new { sleep }`.
  The harness yields a handle so the body can `timer.cancel` early on
  clean exit. Anchors the cancellation samples — no `sleep`-driven
  races (`02-current-audit.md` §5 row §6.4 specifically calls this out).
- `Harness.pair_memory` — `Arcp::Transport::MemoryTransport.pair`
  returning `[server_transport, client_transport]`. The default for
  16 of the 18 rows.
- `Harness.fake_clock(start:)` — constructs an
  `Arcp::Clock::FakeClock.new(now: Time.iso8601(start))` (Phase 04
  deliverable). Exposes `#advance(seconds)`; injected into
  `Arcp::Runtime.new(clock: ...)`. The `heartbeat` (row 10) and
  `lease-expires-at` (row 15) samples are the only consumers; the
  other 16 take the default `Arcp::Clock::SystemClock`.

Signature sketch (for clarity, not for `lib/`):

```ruby
module Harness
  def self.run_or_exit(name, &block); end
  def self.emit(name, asserts:); end
  def self.with_timeout(seconds, task:); end
  def self.pair_memory; end
  def self.fake_clock(start:); end
end
```

## 4. Per-example highlights for v1.1 surfaces

The nine v1.1 rows each demonstrate exactly one spec surface. Below is
what `run.rb` asserts on (the JSON line to `$stdout`) per row — this
is what CI greps for via `jq`.

- **`progress` (row 17, §8.2.1):** the agent emits five `progress`
  bodies with monotonically increasing `current`, fixed `total: 5`,
  `units: 'files'`. Client renders running `current/total` to
  `$stderr` (harness `StderrLogger`); `run.rb` asserts the rendered
  sequence is `[1/5, 2/5, 3/5, 4/5, 5/5]`. Advisory only — the
  protocol takes no action, per spec §8.2.1.

- **`result-chunk` (row 18, §8.4):** the agent calls
  `ctx.stream_result(encoding: 'utf8')` (Phase 04's seam — likely an
  `Async::Queue` wrapper) and pushes ~30 chunks, each ≤ 1 KiB.
  Terminating `job.result` carries `result_id` + `result_size`; the
  client's `handle.result_chunks` returns an `Enumerator::Lazy`
  decoded per `encoding`. `run.rb` asserts `decoded.length ==
  result_size` and rejects inline-mix (the agent attempting to set
  `job.result.payload.result` after streaming raises
  `Arcp::Errors::InvalidRequest` per spec §8.4).

- **`subscribe` (row 13, §7.6):** session A submits `job_R1`; session
  B (same principal, new `Client`) calls `client.subscribe(job_id:
  job_R1, from_event_seq: 0, history: true)`. `job.subscribed.payload
  .subscribed_from` is captured; `run.rb` asserts the replayed event
  count equals `subscribed_from`, the live stream continues without
  gap, and session B's `client.cancel(job_R1)` raises
  `Arcp::Errors::PermissionDenied` (cancel is reserved for the
  submitting session per §7.6).

- **`list-jobs` (row 12, §6.6):** runtime starts ten jobs across two
  agents (`code-refactor`, `test-runner`), five `running` + five
  `pending`. Client calls `client.list_jobs(filter: {status:
  ['running']}, limit: 2)` and consumes the returned `Enumerator
  ::Lazy` via `.first(5)`; `run.rb` asserts pagination traversed two
  intermediate `next_cursor` values and that no `pending` job
  appeared. Filter combinations per §6.6 are spot-checked but not
  exhaustively (that lives in Phase 07 tests).

- **`heartbeat` (row 10, §6.4):** the negotiated
  `heartbeat_interval_sec` is `1`. `run.rb` injects a `FakeClock`,
  advances it by 3 seconds with the client's transport-write side
  silenced, and asserts the runtime closes the transport and the
  client surfaces `Arcp::Errors::HeartbeatLost`. The runtime MUST
  NOT terminate the underlying job — `run.rb` asserts the job
  remains running and is observable via a freshly-resumed session.

- **`ack-backpressure` (row 11, §6.5):** the runtime's `EventLog`
  (Phase 04 module per `02-current-audit.md` §4.3) starts with a
  time-based window of 30 seconds. The agent emits 200 events; the
  client sends `session.ack { last_processed_seq: 100 }`; `run.rb`
  asserts the runtime frees events `1..100` before the 30-second
  window elapses (introspected via a test-only `EventLog#buffer_size`
  reader — Phase 04 marks this `# @api private`). When the client
  intentionally lags (acks only every 200ms while the agent emits
  every 5ms), the runtime emits a `status { phase: 'back_pressure' }`
  event; `run.rb` asserts that event appears.

- **`agent-versions` (row 14, §7.5):** the runtime registers
  `code-refactor` at versions `1.0.0` and `2.0.0` with default
  `2.0.0`. Three `Client#submit` calls are made: `'code-refactor'`
  (resolves to `2.0.0`), `'code-refactor@1.0.0'` (resolves exact),
  `'code-refactor@3.0.0'` (raises
  `Arcp::Errors::AgentVersionNotAvailable`, code from Phase 01 §2).
  `run.rb` asserts the resolved `agent` field in `job.accepted` is
  the fully-qualified `name@version` form per spec §7.5.

- **`lease-expires-at` (row 15, §9.5):** the agent declares
  `lease_constraints.expires_at: clock.now + 60`; `run.rb` advances
  the `FakeClock` by 61 seconds while the agent is mid-loop. The
  next `tool.call` arm of the agent's `case ... in` dispatcher
  receives a `tool_result` with `error.code == 'LEASE_EXPIRED'`;
  `run.rb` asserts `job.error.payload.code == 'LEASE_EXPIRED'` and
  `retryable: false` (Phase 01 §2). Monotonic clock comparison per
  `02-current-audit.md` §5 row §9.5.

- **`cost-budget` (row 16, §9.6):** the agent declares
  `lease_request['cost.budget'] = ['USD:1.00']`. Two `tool.call`
  arms emit `metric { name: 'cost.search', value: '0.42', unit:
  'USD' }` and `metric { name: 'cost.fetch', value: '0.70', unit:
  'USD' }` respectively; runtime decrements the counter via
  `BigDecimal('0.42')` and `BigDecimal('0.70')` (per Phase 01 §1
  row §9.6 and `02-current-audit.md` §2 explicit `bigdecimal` dep).
  Counter goes to `-0.12` USD. A third `tool.call` returns a
  `tool_result` carrying `BUDGET_EXHAUSTED`. `run.rb` asserts the
  third call's `error.code` matches, and that the
  `cost.budget.remaining` metric reached `-0.12` exactly (no
  floating-point drift).

- **`delegation-bounded` (covered inside row 2 `delegate`, §9.4):**
  the parent agent's lease carries `cost.budget: ['USD:5.00']` and
  `lease_constraints.expires_at: parent_deadline`. The parent has
  spent `USD:3.00` at the time it emits a `delegate` event for a
  child job. `run.rb` asserts the child's effective lease
  carries `cost.budget: ['USD:2.00']` (parent remaining at
  delegation time per spec §9.4) and an `expires_at` ≤ the parent's.
  A deliberately-overreaching delegation request (asking for
  `USD:3.00`) is refused with `Arcp::Errors::LeaseSubsetViolation`
  per Phase 01 §1 row §9.4. This collapses the TS
  `delegation-bounded` example into the `delegate` row; the
  assertion list is the union.

## 5. Existing samples retired

The 14 directories currently under `samples/` (`cancellation`,
`capability_negotiation`, `delegation`, `extensions`, `handoff`,
`heartbeats`, `human_input`, `lease_revocation`, `leases`, `mcp`,
`permission_challenge`, `reasoning_streams`, `resumability`,
`subscriptions`) are keyed to the RFC-0001 wire shape — `02-current
-audit.md` §6 lists the wire-shape re-baseline and §9 hands these
samples specifically to Phase 06 for replacement. They are deleted
wholesale alongside the v1.0 re-baseline; the new tree under
`samples/` has one directory per row in §1's table with exactly
`server.rb`, `client.rb`, `run.rb` and the shared
`samples/_harness.rb` — **no `README.md` per sample, no per-sample
`Gemfile`, no fixtures directory.** The samples table in this plan is
the doc; `docs/` (Phase 08) is where prose explanation lives.
