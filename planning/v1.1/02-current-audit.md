# 02 — Current SDK Audit

This SDK does **not** currently implement the v1.0 wire spec the
v1.1 delta in `01-spec-delta.md` is additive over. It implements an
older revision (`RFC-0001-v2.md` → `../spec/docs/draft-arcp-01.md`),
whose message taxonomy and section numbering differ from
`../spec/docs/draft-arcp-02.md` (v1.0) and `draft-arcp-02.1.md`
(v1.1).

Phase 02 calls that out before any v1.1 gap analysis — without
acknowledging the v1.0 re-baseline, "add v1.1 features" reads as
patch work when in reality this is the largest piece of work on the
plan.

## 1. Conformance reality vs the TS reference

The Ruby SDK's `CONFORMANCE.md` (file at `./CONFORMANCE.md`) is a
**5-line stub** that defers to the README's status section. The TS
SDK's `../typescript-sdk/CONFORMANCE.md` is a 407-line section-by-
section v1.0 + v1.1 matrix.

That asymmetry alone is a v1.1 deliverable for Ruby: a full
`CONFORMANCE.md` keyed to `draft-arcp-02.1.md` §4–§16, columns
matching the TS shape (Requirement / Status / Location), one row per
MUST / SHOULD.

What v1.0 (`draft-arcp-02.md`) declares vs what this SDK ships:

| §       | v1.0 wire requirement                                                | Ruby-SDK status                                                                                                                                                                                                                                                       |
| ------- | -------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| §5.1    | Envelope: `arcp: "1"`, `id`, `type`, `session_id`, `event_seq`, `payload` | **Diverges.** `lib/arcp/envelope.rb` `Data.define`s a 19-field envelope (with `source`, `target`, `stream_id`, `subscription_id`, `span_id`, `parent_span_id`, `correlation_id`, `causation_id`, `priority`, `extensions`). `arcp` field is "1.0" per `Arcp::PROTOCOL_VERSION`, not literal `"1"`. No `event_seq`. |
| §6.1    | Bearer token in `session.hello.payload.auth.token`                   | **Diverges.** `lib/arcp/auth/{bearer,jwt}.rb` exist; auth lands inside `session.open` per `lib/arcp/messages/session.rb:9`, not `session.hello`. Challenge/response loop (`session.challenge` / `session.authenticate`) is RFC-0001-specific.                              |
| §6.2    | `session.hello` ↔ `session.welcome`; agents inventory; resume_token  | **Missing wire shape.** No `Hello`/`Welcome` payload classes; closest pair is `Open` + `Accepted` (`lib/arcp/messages/session.rb:9,12`). Capabilities exist (`lib/arcp/capabilities.rb`) but the features-list / agents-rich-shape do not.                                |
| §6.3    | Resume via hello.resume + last_event_seq + buffer replay             | **Partial.** `lib/arcp/messages/control.rb` declares `resume` (top-level); `lib/arcp/store/event_log.rb` is a SQLite log. Wire seam is wrong (resume is its own envelope, not part of hello).                                                                              |
| §6.7    | `session.bye` clean close                                            | **Diverges.** `session.close` + `session.evicted` exist; semantic intent overlaps.                                                                                                                                                                                       |
| §7.1    | `job.submit` → `job.accepted`                                        | **Missing.** No `job.submit` payload; jobs surface via `job.started`/`job.accepted`/`job.completed`/`job.failed`/`job.cancelled`/`job.heartbeat`/`job.progress` (`lib/arcp/messages/execution.rb`) — different lifecycle.                                                |
| §7.4    | Cancellation                                                         | **Diverges.** `lib/arcp/messages/control.rb` declares `cancel` + `cancel.accepted` + `cancel.refused`. v1.0 treats cancel as part of the job lifecycle without separate accept/refuse envelopes.                                                                          |
| §8.1    | `job.event` envelope with `kind`                                     | **Missing.** No single `job.event`; events are typed top-level wire messages (e.g. `event.emit`, `log`, `metric`, `trace.span`, `stream.chunk`). The v1.0 model unifies these under one `job.event` envelope with a `kind` discriminant.                                  |
| §8.2    | Event kinds: log, thought, tool_call, tool_result, status, metric, … | **Diverges.** Tool surfaces (`tool.invoke`/`tool.result`/`tool.error`) are top-level wire messages, not `kind` values inside `job.event`. Logs are top-level `log` envelopes (`lib/arcp/messages/telemetry.rb`).                                                          |
| §9      | Leases: namespace grammar, subsetting                                | **Partial.** `lib/arcp/runtime/lease_manager.rb` + `lib/arcp/messages/permissions.rb` (`lease.granted`/`lease.refresh`/`lease.extended`/`lease.revoked`/`permission.request`/`permission.grant`/`permission.deny`). Wire shape and lifecycle do not match §9.2 grammar.        |
| §10     | Delegation                                                           | **Partial.** No top-level `delegate` event; delegation likely happens via `tool.invoke` + `permission.request` in current shape.                                                                                                                                          |
| §11     | Trace propagation (W3C 32-hex `trace_id` on envelope)                | **Partial.** Envelope has `trace_id` + `span_id` + `parent_span_id` (more than spec requires); `lib/arcp/trace.rb` is fiber-local context.                                                                                                                                |
| §12     | 12 canonical error codes                                             | **Diverges.** `lib/arcp/error_code.rb` ships 21 gRPC-style codes (`OK`, `CANCELLED`, `UNKNOWN`, `INVALID_ARGUMENT`, `DEADLINE_EXCEEDED`, `NOT_FOUND`, `ALREADY_EXISTS`, `PERMISSION_DENIED`, `RESOURCE_EXHAUSTED`, `FAILED_PRECONDITION`, `ABORTED`, `OUT_OF_RANGE`, `UNIMPLEMENTED`, `INTERNAL`, `UNAVAILABLE`, `DATA_LOSS`, `UNAUTHENTICATED`, `HEARTBEAT_LOST`, `LEASE_EXPIRED`, `LEASE_REVOKED`, `BACKPRESSURE_OVERFLOW`), not the 12 spec codes. See §3.4 below. |

Status summary: **the Ruby SDK is not v1.0 conformant.** The
v1.1-delta work (`01-spec-delta.md` §1) sits on top of a wire-shape
re-baselining. Phase 10 ranks this as the largest milestone.

## 2. `arcp.gemspec` decoded

```
arcp · Apache-2.0 · v0.1.0 · PROTOCOL_VERSION = '1.0'
```

| Field                  | Value                            | Comment for v1.1                                                                                                                            |
| ---------------------- | -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `required_ruby_version`| `>= 3.4.0`                       | Higher than the bootstrap floor (3.3+). `lib/arcp/envelope.rb` uses `Data.define` (3.2+) and pattern matching (3.0+); no 3.4-specific construct in `lib/` justifies tightening. Phase 03 must defend keeping 3.4 or relax to 3.3.                              |
| `Arcp::PROTOCOL_VERSION` | `'1.0'`                        | Misleading — the wire shape is RFC-0001 (`draft-arcp-01.md`), not v1.0 (`draft-arcp-02.md`). v1.1 work will set this to `'1.1'` once the re-baseline lands. The wire envelope literal should also flip from `arcp: "1.0"` to `arcp: "1"` per spec §5.1.        |
| `async`                | `~> 2.0`                         | Aligned with the bootstrap concurrency pick (`socketry/async`). Defend.                                                                     |
| `async-websocket`      | `~> 0.30`                        | Aligned with the WS client/server pick. Defend Falcon-side server choice in Phase 03.                                                       |
| `dry-cli`              | `~> 1.0`                         | Used by `lib/arcp/cli.rb`. **Violates the bootstrap rule** "No Rails-coupled deps in core" only in spirit (`dry-cli` is not Rails); but CLI generally should not be in the core gem. Phase 04: extract `arcp/cli.rb` to a separate `arcp-cli` sub-gem.            |
| `json_schemer`         | `~> 2.0`                         | Not on Phase 03's seed list. **Justify or drop.** v1.0 / v1.1 wire validation does not require JSON Schema at runtime; pattern matching + `Data.define` keyword validation suffices. Likely vestigial from RFC-0001 capability discovery.                                              |
| `jwt`                  | `~> 2.0`                         | Used by `lib/arcp/auth/jwt.rb`. v1.0 §6.1 only requires bearer; JWT is a SHOULD-NOT-be-mandatory dep in core. Phase 04: split into `arcp-auth-jwt`.                                                                                                                |
| `logger`               | `~> 1.6`                         | Ruby 3.4 unbundled `logger` from stdlib; declaring it explicitly is correct. Keep.                                                          |
| `sqlite3`              | `~> 2.0`                         | Used by `lib/arcp/store/event_log.rb` for the resume buffer. **Runtime-side only.** Move out of core if the SDK splits client / runtime gems (Phase 04 decides); otherwise keep but document as a runtime-only path.                                            |
| (dev) `bundler-audit`  | latest                           | Keep — supply-chain hygiene.                                                                                                                |
| (dev) `rake`           | `~> 13.0`                        | Aligned.                                                                                                                                    |
| (dev) `rspec`          | `~> 3.13`                        | Aligned with Phase 03's test pick.                                                                                                          |
| (dev) `rubocop` + plugins | `~> 1.60`                      | Aligned with Phase 03's lint pick (incumbent — not `standardrb`).                                                                           |
| (dev) `simplecov`      | `~> 0.22`                        | Aligned with the 87% line+branch floor; **branch coverage must be enabled explicitly** (`SimpleCov.enable_coverage :branch`) — Phase 07.    |
| (dev) `yard`           | `~> 0.9`                         | Aligned with Phase 08 docs pick. **No `.yardopts` file in tree** — Phase 08 adds one.                                                       |
| **Not declared**       | `opentelemetry-api`, `securerandom`, `bigdecimal` | Phase 03 adds `opentelemetry-api` for §11 trace attributes; `securerandom` is stdlib (3.4+ `SecureRandom.uuid_v7`); `bigdecimal` is required to land §9.6 cost-budget decimal math without `Float` drift, and is **no longer bundled in Ruby 3.4** — must be an explicit `add_dependency`. |

`spec.files` glob includes `sig/**/*.rbs`, but there is **no `sig/`
directory** in the tree (`ls sig` errors). RBS sig writing is a v1.1
deliverable for Phase 04 / Phase 08.

The `arcp` executable lives at `exe/arcp`; the CLI implementation
(`lib/arcp/cli.rb`) depends on `dry-cli`. Splitting the CLI into a
sub-gem (Phase 04) does not break the executable name — `arcp-cli`
ships `exe/arcp` and depends on `arcp`.

## 3. Style & quality gates

| Tool / config | Current setting | Don't regress in v1.1                                                                                                                |
| ------------- | --------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| RuboCop       | `TargetRubyVersion: 3.4` (`.rubocop.yml:6`); rubocop-performance, rubocop-rake, rubocop-rspec plugins | Keep TargetRubyVersion in sync with the gemspec floor. New code must pass `bundle exec rubocop` (pre-commit lefthook).               |
| `STYLE.md` deviations | `Layout/LineLength: 110` (specs excluded); `Metrics/MethodLength: 40`; `Metrics/ClassLength: 400`; `Metrics/ModuleLength: 400`; documented in `STYLE.md` lines 23–46 | New v1.1 code respects these. Long state-machine methods in `lib/arcp/runtime/*` would already exceed `Max: 40`; they cite `STYLE.md`'s "runtime / protocol orchestration objects are allowed to stay cohesive even when they exceed toy-size limits" — same accommodation for v1.1 work, but log outliers in `REFACTOR_BACKLOG.md` (per STYLE). |
| `Style/FrozenStringLiteralComment` | `Enabled: true, EnforcedStyle: always` | Every new `.rb` file must open with `# frozen_string_literal: true`. PR template checklist item.                                  |
| Lefthook      | `pre-commit: rubocop --force-exclusion`; `pre-push: rake` (the rake default runs `rspec` + `rubocop`) | New v1.1 work runs the same gates. No new pre-commit hooks unless Phase 07 needs RBS / Sorbet type checking.                            |
| SimpleCov     | `~> 0.22` declared but **branch coverage not enabled in `spec_helper.rb`** (default config) | Phase 07 enables `SimpleCov.enable_coverage :branch` and sets `minimum_coverage_by_file 87, branch: 87` — the bootstrap floor.       |
| YARD          | `~> 0.9` declared but no `.yardopts` | Phase 08 adds `.yardopts` pointing at `lib/**/*.rb` with `--output-dir docs/api`.                                                  |
| RBS / Sorbet  | **None.** No `sig/` dir; no `srb` config | Phase 03 picks one (RBS + steep vs Sorbet). Phase 04 specifies which seams get sigs first.                                       |

Static-typing posture is **not** as strict as PHP-SDK's PHPStan max +
Psalm (Phase 02 of the PHP plan). Phase 03 must defend either
introducing RBS sigs alongside `lib/` or accepting "no type checker"
for v1.1 and deferring.

## 4. File tree → target module mapping

The current top-level module (`Arcp`) is correct. The sub-module
shape needs work for v1.0 / v1.1 alignment. Phase 04 owns the
final layout; this audit captures the current vs target.

### 4.1. `lib/arcp/` modules — current

```
Arcp::Auth          — AuthScheme, BearerAuth, JwtAuth
Arcp::CLI           — dry-cli-based commands (in lib/arcp/cli.rb monolith)
Arcp::Client        — Client (lib/arcp/client/client.rb)
Arcp::Envelope      — Data.define with 19 fields (lib/arcp/envelope.rb)
Arcp::Capabilities  — capability advertisement (lib/arcp/capabilities.rb)
Arcp::Error         — base StandardError subclass (lib/arcp/error.rb)
Arcp::ErrorCode     — 21-string gRPC-shaped constants (lib/arcp/error_code.rb)
Arcp::Extensions    — extension namespace registry (lib/arcp/extensions.rb)
Arcp::Ids           — typed IDs: MessageId, JobId, SessionId, StreamId, SubscriptionId, …
Arcp::Json          — JSON helpers (lib/arcp/json.rb)
Arcp::Messages      — 14 message-payload modules across 8 files
Arcp::MessageTypeRegistry — wire-type → payload-class table (lib/arcp/message_type.rb)
Arcp::Priority      — enum-ish constants
Arcp::Runtime       — Runtime, JobManager, LeaseManager, StreamManager,
                      SubscriptionManager, ArtifactStore, PendingRegistry,
                      Session, SessionHelper
Arcp::Store         — EventLog (SQLite-backed)
Arcp::Trace         — fiber-local trace context
Arcp::Transport     — Transport (abstract), MemoryTransport, StdioTransport,
                      WebSocketTransport
```

41 `.rb` files, ~14 message-payload modules.

### 4.2. `Arcp::Messages` wire types (current)

From grepping `'session.*'`-style literals across `lib/arcp/messages/`:

`ack`, `artifact.{fetch,put,ref,release}`, `backpressure`, `cancel`,
`cancel.accepted`, `cancel.refused`, `event.emit`,
`human.choice.{request,response}`, `human.input.{cancelled,request,response}`,
`interrupt`, `job.{accepted,cancelled,completed,failed,heartbeat,progress,started}`,
`lease.{extended,granted,refresh,revoked}`, `log`, `metric`, `nack`,
`permission.{deny,grant,request}`, `ping`, `pong`, `resume`,
`session.{accepted,authenticate,challenge,close,evicted,open,refresh,rejected,unauthenticated}`,
`stream.{chunk,close,error,open}`, `subscribe`, `subscribe.{accepted,closed,event}`,
`tool.{error,invoke,invocations,result}`, `trace.span`, `unsubscribe`.

That's **58 wire-type literals**. Compare with the v1.0 / v1.1 target
set (~16 envelope types after unifying events into `kind`s inside
`job.event`).

### 4.3. Target module map (Phase 04 sketch)

```
Arcp                — version, top-level
Arcp::Envelope      — Data.define (8 fields, not 19)
Arcp::Serializer    — JSON in/out (rename Arcp::Json)
Arcp::Session       — Feature, CapabilitySet, AgentInventory, AgentEntry,
                      Hello, Welcome, Bye, Error, Ack (§6.5),
                      Ping/Pong (§6.4), ListJobs/JobsResponse (§6.6)
Arcp::Job           — Submit, Accepted, Event, Result, Error, Cancel,
                      Subscribe, Subscribed, Unsubscribe
Arcp::Job::Event    — Kind module, Progress (§8.2.1), ResultChunk (§8.4),
                      Log, Thought, ToolCall, ToolResult, Status, Metric,
                      TraceSpan, Delegate
Arcp::Lease         — Capability, LeaseRequest, EffectiveLease,
                      LeaseConstraints (§9.5 expires_at), CostBudget (§9.6)
Arcp::Errors        — Error base + 15 final subclasses (one per spec code),
                      ErrorCode constants module (15 entries)
Arcp::Auth          — AuthScheme (interface), BearerAuth (in core);
                      JwtAuth moves to `arcp-auth-jwt` sub-gem
Arcp::Client        — Arcp::Client (rename Arcp::Client::Client)
Arcp::Runtime       — Runtime, JobManager, LeaseManager, EventLog,
                      SubscriptionManager (track v1.1 §7.6 subscribe),
                      ArtifactStore (decide: keep? — see Phase 04)
Arcp::Transport     — Transport, MemoryTransport, WebSocketTransport,
                      StdioTransport
Arcp::Trace         — W3C traceparent helpers; rename `Trace` -> `Tracing`
                      if Phase 04 prefers
Arcp::CLI           — moves to `arcp-cli` sub-gem (out of core)
```

Migration cost: roughly **half of `lib/arcp/` is renamed or
relocated.** This is the bulk of the milestone after the wire-shape
rework.

## 5. v1.1 feature × current-SDK gap matrix

Risk legend: **L** (low — additive, no protocol-shape change),
**M** (medium — requires aligning with v1.0 wire shape first),
**H** (high — touches concurrency, cancellation, or distributed
state semantics in a way unique to Ruby's Fiber scheduler).

| v1.1 §  | Feature                       | Status      | Target module                                      | Risk | Ruby-specific risk note                                                                                                                                                                                                                                            |
| ------- | ----------------------------- | ----------- | -------------------------------------------------- | ---- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| §6.2    | Capability negotiation (features list, agents rich shape) | missing  | `Arcp::Session::{Feature,CapabilitySet,AgentInventory}` | M | The closed-by-convention `Feature::ALL.freeze` table (Phase 01 §3.1) plus `Data.define`-based `CapabilitySet#intersect` make this small; the harder part is reshaping the hello/welcome wire to v1.0 first (§1 row §6.2). |
| §6.4    | Heartbeat (`session.ping`/`session.pong`) | partial wire, missing protocol | `Arcp::Session::{Ping,Pong}` | M | `lib/arcp/messages/control.rb` already declares `ping`/`pong`; v1.0 names them `session.ping`/`session.pong`. The driver is an `Async::Task` timer registered on `welcome`; **risk:** the timer is fiber-bound — when the session closes, the task must be `.stop`'d, not garbage-collected. Easy leak.    |
| §6.5    | Event ack (`session.ack`)     | partial      | `Arcp::Session::Ack`                                | M | Current top-level `ack` envelope (`lib/arcp/messages/control.rb`); v1.0 names it `session.ack` and its body is `{ last_processed_seq: }`. `lib/arcp/store/event_log.rb` (SQLite) needs an "advisory free up to seq" path; current implementation likely keeps everything to the resume window.                            |
| §6.6    | Job listing (`session.list_jobs`/`session.jobs`, cursored) | missing  | `Arcp::Session::{ListJobs,JobsResponse}`            | H | Cursor pagination across a long-lived `Async` task needs explicit cancellation via `Async::Task#stop`; if the SDK reads from `lib/arcp/store/event_log.rb` (SQLite, blocking I/O) the per-page read isn't fiber-suspending, but the surrounding loop is — easy to leak a SQLite cursor on `stop`. Need explicit `ensure` block closing the prepared statement. |
| §7.5    | Agent versioning (`name@version`) | missing | `Arcp::Session::AgentEntry` + parser in `Arcp::Job::Submit` | M | Parser is `name, version = ref.split('@', 2)`; the harder part is plumbing through `JobManager` and `SubscriptionManager` so listings echo `agent: "name@version"`. v1.0 flat-string compat is `AgentEntry.from_flat(name)` (Phase 01 §3.3).                                                                                |
| §7.6    | Subscription (`job.subscribe`/`job.subscribed`/`job.unsubscribe`) | partial | `Arcp::Job::{Subscribe,Subscribed,Unsubscribe}`     | H | Current `lib/arcp/messages/subscriptions.rb` is a generic "subscribe to a stream" message; v1.0/v1.1 means specifically attaching to a job's event stream from a different session. **Risk:** authorization (`PERMISSION_DENIED` per spec) is per-principal across sessions; current `SubscriptionManager` does not model cross-session principals; needs design work, not just a new class. |
| §8.2.1  | `progress` event kind         | partial      | `Arcp::Job::Event::Progress`                        | L | `lib/arcp/messages/execution.rb` defines `job.progress` as a top-level message; v1.0 makes progress a `kind` inside `job.event`. Move the body shape, drop the top-level message after v1.0 re-baseline.                                                                                                                |
| §8.4    | `result_chunk` event + streamed `job.result` | missing | `Arcp::Job::Event::ResultChunk`                     | H | `Async::Queue` for the chunk stream; assembly on the consumer side is an `Enumerator::Lazy` decoding `utf8`/`base64` strings. **Risk:** if the agent raises mid-stream the runtime MUST emit `job.error` with the streamed `result_id`; cleanup paths under `Async::Stop` propagation need an `ensure` block, not a `rescue`. |
| §9.5    | Lease expiration (`lease_constraints.expires_at`) | missing | `Arcp::Lease::LeaseConstraints`                    | M | ISO-8601 UTC `Z` via `Time.iso8601(s)` then assert `time.utc?`; surface as `Arcp::Errors::InvalidRequest` client-side before submit. Enforcement is on every `LeaseManager` check — keep the comparison `Process.clock_gettime(Process::CLOCK_MONOTONIC) >= expires_at_monotonic` rather than `Time.now` to avoid wall-clock skew on long-lived jobs.        |
| §9.6    | `cost.budget` capability      | missing      | `Arcp::Lease::CostBudget`                           | H | Per-currency counters using `BigDecimal` (Phase 03 must add the dep — Ruby 3.4 unbundled bigdecimal). With `Async` Fibers, counters are read-modify-write under cooperative scheduling, so non-atomic operations between two `await`s are safe **only** if no `Fiber.yield`-equivalent happens between read and decrement. Document and test (Phase 07 §3.8 equivalent). |
| §9.4    | Delegation subsetting (budget, expires_at) | partial | `Arcp::Lease::LeaseSubsetting`                    | M | Existing `lib/arcp/runtime/lease_manager.rb` subsetting needs two new constraints; cross-fiber read of "parent remaining budget at delegation time" must snapshot, not race.                                                                                              |
| §11     | Trace attrs (`arcp.lease.expires_at`, `arcp.budget.remaining`) | partial | `Arcp::Trace` + OTEL middleware                    | L | `opentelemetry-api` gem dep; pure additive. `lib/arcp/trace.rb` already uses fiber-local storage which is correct for `Async`-spawned fibers.                                                                                                                              |
| §12     | Three new error codes         | missing      | `Arcp::Errors::{AgentVersionNotAvailable,LeaseExpired,BudgetExhausted}` | L | Three small subclasses of `Arcp::Error`. Note: `lib/arcp/error_code.rb:23` already lists `LEASE_EXPIRED` as a constant but with no enforcement path. The broader 21 gRPC-style code retirement (§3.4 below) is a v1.0 re-baseline concern, not v1.1.                                                                       |

## 6. Items that are **not** v1.1 gaps but a v1.0 re-baseline (call out for Phase 10)

These need fixing for any v1.1 work to land on a conformant base.
Phase 10 ranks them ahead of v1.1 features.

1. **Envelope shape.** Reduce from 19 fields to the §5.1 set
   (`arcp`, `id`, `type`, `session_id`, `trace_id`, `job_id`,
   `event_seq`, `payload`). Drop `source`, `target`, `stream_id`,
   `subscription_id`, `span_id`, `parent_span_id`, `correlation_id`,
   `causation_id`, `priority`, `extensions` from the top level —
   most of these are RFC-0001 specific or move into payloads.
2. **`arcp` field literal.** `Arcp::PROTOCOL_VERSION` flips from
   `'1.0'` to `'1'` per §5.1; the wire literal is `"1"`, not the
   semver string.
3. **Session handshake.** Rename `session.open` /
   `session.accepted` / `session.authenticate` / `session.challenge`
   / `session.rejected` / `session.unauthenticated` ➜ `session.hello`
   / `session.welcome` / `session.error`. Auth folds into the hello
   payload.
4. **Job submission.** Replace `job.started` (as a top-level submit
   trigger) with `job.submit` ➜ `job.accepted`.
5. **Event unification.** Collapse `log` / `metric` / `event.emit` /
   `trace.span` / `tool.invoke` / `tool.result` / `tool.error` /
   `stream.chunk` etc. into `job.event { kind:, body: }` per §8.2.
6. **Error taxonomy.** Replace the 21 gRPC-style codes in
   `lib/arcp/error_code.rb` with the 15-code (12 v1.0 + 3 v1.1)
   set. The retired codes (`OK`, `UNKNOWN`, `INVALID_ARGUMENT`,
   `DEADLINE_EXCEEDED`, `NOT_FOUND` (→ `JOB_NOT_FOUND`),
   `ALREADY_EXISTS` (→ `DUPLICATE_KEY`), `RESOURCE_EXHAUSTED`,
   `FAILED_PRECONDITION`, `ABORTED`, `OUT_OF_RANGE`,
   `UNIMPLEMENTED`, `UNAVAILABLE`, `DATA_LOSS`, `LEASE_REVOKED`,
   `BACKPRESSURE_OVERFLOW`) either rename or delete. The
   `RETRYABLE_BY_DEFAULT` / `NON_RETRYABLE_BY_DEFAULT` sets
   re-keyed to the 15-code set.
7. **`session.bye`** clean close (§6.7) replaces `session.close` /
   `session.evicted`.
8. **`CONFORMANCE.md`** rewritten to mirror the TS 407-line matrix.
9. **`lib/arcp/cli.rb` + `exe/arcp`** moves out of core (separate
   `arcp-cli` sub-gem). `dry-cli` dep moves with it.
10. **`json_schemer`** removed (no runtime schema validation needed —
    typed `Data.define` keyword args + pattern matching do it).
11. **`Arcp::Auth::JwtAuth`** moves to `arcp-auth-jwt`. `jwt` gem
    dep moves with it.

## 7. Deployment-model constraint (Ruby-specific)

The runtime is **a long-lived process**: an `Async` reactor running
on `Async::Reactor` with the Fiber scheduler. That implies the
runtime is hosted by:

- A daemon (systemd, Docker, Kamal).
- `falcon` (an `Async`-native Rack server — first-class).
- ActionCable inside a Rails app's `puma`/`falcon` process (a
  bridge, see Phase 05).

It is **not** hosted by:

- A `puma`-per-request worker with classic blocking I/O — a heartbeat
  timer + event buffer + `job.subscribe` listener that lasts a job's
  lifetime do not survive a per-request worker model. Each request
  gets a fresh worker, the fiber dies.
- A `bundle exec arcp serve --transport stdio` run scoped to a single
  CLI invocation, except for the stdio transport itself, which
  terminates with the parent.

**Phase 08 (docs) MUST state this clearly:** the ARCP Ruby runtime
on a network transport is a daemon process, typically via Falcon.
ActionCable provides an in-Rails embedding via WebSocket only.

## 8. Tests baseline

```
spec/
  unit/            — 8 files: envelope, error, extensions, ids,
                     job_manager, messages, store/, version
  integration/    — 13 files: handshake, job_lifecycle, cancellation,
                     resume, stream, subscription, permission_lease,
                     interrupt, human_input, artifact, extension_unknown,
                     stdio_transport, websocket_transport
  e2e/             — 1 file: relay_scenario_spec.rb
```

22 spec files total. Coverage tool (`simplecov`) declared but
**branch coverage not enabled** by default — Phase 07 wires
`SimpleCov.enable_coverage :branch` and a minimum-coverage gate.

Existing fixtures are likely keyed to the RFC-0001 wire shape and
will need regeneration after the v1.0 re-baseline lands.

## 9. Hand-off to Phases 3–9

| Phase | What this audit hands them                                                                                                                                                                                                |
| ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 03    | `gemspec` decoded (§2). Defend keeping `async` + `async-websocket`; justify dropping `json_schemer`; decide RBS vs Sorbet; pick mutation tool (`mutant` vs skip); reject `dry-cli` and `jwt` in core.                       |
| 04    | Current → target module map (§4). v1.0 re-baseline list (§6). Deployment constraint (§7). RBS / Sorbet boundary.                                                                                                          |
| 05    | Existing `Arcp::Transport::WebSocketTransport` is a client-side `async-websocket` connection (likely); runtime-side WS upgrade attachment will live in `arcp-falcon` and `arcp-rack` (Phase 05).                              |
| 06    | Existing 14 sample directories under `samples/` are keyed to RFC-0001 wire shape; will need rewrite. Map to v1.1 18-example list when planning.                                                                            |
| 07    | RSpec + SimpleCov declared but branch coverage not enabled; no mutation testing; no async-rspec dep. Phase 07 sets all three.                                                                                              |
| 08    | `CONFORMANCE.md` is a 5-line stub; full v1.0+v1.1 matrix needed. `RFC-0001-v2.md` points at `draft-arcp-01.md` — Phase 08 updates the pointer to `draft-arcp-02.1.md`. No `.yardopts` — add one.                            |
| 09    | No existing diagrams to extend; greenfield.                                                                                                                                                                                |
