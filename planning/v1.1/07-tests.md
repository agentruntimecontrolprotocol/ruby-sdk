# 07 — Testing Strategy (ARCP Ruby SDK v1.1)

Floor: **87% lines AND branches** (`BOOTSTRAP.md` Phase 7). The
`02-current-audit.md` §3 + §8 calls out two gaps the spec_helper
currently ignores: branch coverage is not enabled (SimpleCov runs in
line-only mode at `spec/spec_helper.rb:7`) and there is no
Fiber-aware test harness. This plan closes both, layers tests over
the v1.0 re-baseline + v1.1 features from `01-spec-delta.md`, and
exhausts every new feature with one named spec file.

## 1. Test stack

| Concern | Pick | Why over the candidate | Status in `Gemfile` |
| --- | --- | --- | --- |
| Spec runner | **RSpec 3.13** | Incumbent (`Gemfile:10`); 22 spec files already live under `spec/unit`, `spec/integration`, `spec/e2e`. Minitest swap is gratuitous churn. | present |
| Coverage | **SimpleCov 0.22** with `enable_coverage :branch` | Incumbent (`Gemfile:15`). Branch mode is one config line — `Coverage` stdlib supports it under MRI 2.5+; the audit §3 calls out its absence as a gap. | present, config delta below |
| Fiber harness | **`async-rspec`** (`~> 1.17`) | `Async::RSpec::Reactor` shared context spins a reactor per example so specs can write `it 'pongs within interval' do ... Async { ... }.wait ... end` without a hand-rolled `Sync { }` wrapper. Rejecting `concurrent-ruby` thread pools: the production I/O path is Fibers, tests must be too. | **add to dev group** |
| Lint | **RuboCop 1.60** | Incumbent (`Gemfile:11`) with `rubocop-performance`, `rubocop-rake`, `rubocop-rspec`. Runs as a separate CI gate per `.rubocop.yml`, not bundled into `bundle exec rspec`. | present |
| Mutation | **`mutant` (nightly, target MSI ≥ 95% on `lib/arcp/envelope.rb`, `lib/arcp/session/capability_set.rb`, `lib/arcp/lease/cost_budget.rb`)** | Per-PR is too slow — mutant on a 41-file gem easily blows 30+ minutes per run; nightly GitHub Actions job under `--since main` filters to changed files. `mutest` rejected: lower adoption, no SimpleCov interop. Skip mutation on the runtime state-machine modules (too many timing-dependent mutations survive). Cost budget: 10 CI minutes nightly. | **add to dev group**, nightly-only |
| Property testing | **skip** | The SDK is value-object plumbing — `Data.define` types with closed unions of payload classes. The fuzz target would be JSON round-trip on `Envelope`, which is already covered by table-driven specs against `spec/fixtures/envelopes/`. `rantly` ruled out; reconsider if `result_chunk` decoding ends up touching binary edge cases (it doesn't — encoding is `utf8`/`base64` only per §8.4). | not added |
| Time control | **hand-rolled `FakeClock`** with `Process.clock_gettime(Process::CLOCK_MONOTONIC)` seam | Incumbent runtime (`02-current-audit.md` §5 row §9.5) uses monotonic clock to avoid wall-clock skew. Test seam is a `module Arcp::Clock; def self.monotonic = Time.now ...` indirection mocked via RSpec stubs. `timecop` rejected: monkey-patches `Time.now` globally and won't catch monotonic-clock reads. | code change in §5 |

## 2. Layered test plan

Four layers plus the conformance harness. Each layer's directory
matches the existing tree (`spec/unit/`, `spec/integration/`,
`spec/e2e/`) so the `.rspec` `--default-path spec` keeps working.

### 2.1 Envelope unit — `spec/unit/`

Files: `envelope_spec.rb`, `session_spec.rb`, `job_spec.rb`,
`lease_spec.rb`, `job_event_spec.rb`.

Round-trip shape for every wire type: build the Ruby value object via
`Arcp::Envelope.new(...)`, call `#to_h`, hand to
`Arcp::Serializer.dump` (renamed from `Arcp::Json` per `02-current-audit.md`
§4.3), assert the JSON bytes match a fixture under
`spec/fixtures/envelopes/13.x__*.json`, then run the bytes back
through `Serializer.load` → `Envelope.from_h` → pattern-match the
payload back to its concrete `Data` subclass, and assert `==`
against the original (`Data.define` gives structural equality
without `def ==`).

Decoder rejection paths: omit a required key (`event_seq`,
`session_id`); supply a wrong type (`event_seq: "12"` not an
`Integer`); raise `Arcp::Errors::InvalidRequest` before the
envelope is constructed.

RSpec descriptor lines (illustrative):

- `describe Arcp::Envelope do ... it 'round-trips session.hello' ... end`
- `describe '.from_h on malformed input' do ... it 'rejects non-Integer event_seq' ... end`

### 2.2 Message unit — `spec/unit/messages_spec.rb`

Every concrete payload class's wire-type literal asserted against the
`01-spec-delta.md` §1 table and the spec §7 + §8 inventory. The
existing `lib/arcp/message_type.rb` registry is replaced; the test
keeps it honest.

A separate `MessageCatalogContractSpec` iterates the v1.1 wire-type
set against `spec/fixtures/spec-message-types.json` — a file
generated once from `draft-arcp-02.1.md` §7 + §8 tables, checked in.
If a new wire type lands without an entry in the registry (or vice
versa), the spec fails loudly with the unmatched literal in the
message. This is the only place we test "the registry is
exhaustive"; everywhere else trusts the constants.

### 2.3 State-machine unit — `spec/unit/`

Files: `session_state_spec.rb`, `job_state_spec.rb`,
`subscribe_state_spec.rb`.

Session FSM (§6): `IDLE → OPENING → OPEN → CLOSING → CLOSED` plus
the heartbeat-loss edge `OPEN → CLOSED` with reason
`HEARTBEAT_LOST`. Job FSM (§7 + §12): `PENDING → ACCEPTED → RUNNING
→ {SUCCEEDED, ERROR, CANCELLED}` with the v1.1 terminals
`LEASE_EXPIRED` and `BUDGET_EXHAUSTED` both mapping to
`final_status: "error"` per §12. Subscribe FSM (§7.6):
`ATTACHED → DETACHED` via `unsubscribe`; `cancel` from a
subscribe-only handle short-circuits to
`Arcp::Errors::NotAuthorized` without writing to the transport.

### 2.4 Integration — `spec/integration/`

Two transports. `MemoryTransport.pair` (existing seam in
`lib/arcp/transport/memory_transport.rb` per `02-current-audit.md`
§4.1) drives handshake, submit, event flow, cancel, resume — the
fast path. A WebSocket loopback fixture binds an `async-websocket`
server to `127.0.0.1:0` (ephemeral port; the OS chooses, so parallel
RSpec workers don't collide) inside `Async::RSpec::Reactor`, and
the test connects via `Arcp::Transport::WebSocketTransport`. This
covers the transport-real path that `MemoryTransport` would let
through.

Existing files to retain (rewrite, not replace, after the
re-baseline): `handshake_spec.rb`, `job_lifecycle_spec.rb`,
`cancellation_spec.rb`, `resume_spec.rb`, `subscription_spec.rb`,
`permission_lease_spec.rb`, `websocket_transport_spec.rb`. The
fixture references currently point at RFC-0001 wire shapes
(`02-current-audit.md` §8) — those get deleted, not edited (see §8
below).

### 2.5 Conformance harness — `spec/conformance/` (new directory)

One spec per row of `CONFORMANCE.md` (which Phase 08 rewrites to
match the TS 407-line shape per `02-current-audit.md` §1). Each
spec is tagged `:conformance`, runs under a dedicated rake task —
`bundle exec rake conformance` — and produces a JSON report at
`tmp/conformance-report.json` keyed to the spec §. CI publishes the
report as a build artifact. This is the canonical signal "Ruby SDK
is v1.1 conformant," not the headline RSpec pass count.

## 3. v1.1-specific specs

One spec file per feature in `01-spec-delta.md` §1. Pattern-matching
idioms are the assertion vocabulary (see §4).

### `HeartbeatSpec` — `spec/integration/heartbeat_spec.rb` (§6.4)

`Arcp::Clock.monotonic` stubbed to advance past 2× the negotiated
`heartbeat_interval_sec` without the runtime emitting `session.pong`.
Assert `Arcp::Errors::HeartbeatLost` raised from the awaiting client
task. Critically: a `Job` returned by an earlier `submit_job` call
in the same session still has `JobStatus::RUNNING` afterwards — the
runtime **MUST NOT** terminate jobs on heartbeat loss per §6.4 and
`01-spec-delta.md` row §6.4. Re-read the job state from a fresh
`session.list_jobs` over a new session and confirm.

### `AckSpec` — `spec/unit/ack_spec.rb` + `spec/integration/ack_spec.rb` (§6.5)

Unit: build `Arcp::Session::Ack.new(last_processed_seq: 60)`,
assert `to_h == { last_processed_seq: 60 }`. Integration: client
sends `session.ack { last_processed_seq: 60 }`; assert
`Arcp::Runtime::EventLog#floor` advanced to 60 ahead of the
time-based eviction window. Use the in-memory `EventLog` test
double, not the SQLite-backed prod implementation, to keep this
under `Async::RSpec::Reactor` without I/O.

### `ListJobsSpec` — `spec/integration/list_jobs_spec.rb` (§6.6)

Submit 30 jobs under principal A; request `session.list_jobs` with
`limit: 10`; assert exactly three pages via `next_cursor`. Then
open a second session as principal B and assert B's `list_jobs`
yields none of A's jobs — per-principal visibility from
`01-spec-delta.md` row §6.6. The `Enumerator::Lazy` returned by
`Client#list_jobs` (per `04-architecture.md` once written; current
`02-current-audit.md` §5 row §6.6 flags this) is consumed with
`.first(50).to_a` — verifies lazy paging doesn't over-read.

### `SubscribeSpec` — `spec/integration/subscribe_spec.rb` (§7.6)

Session A submits a job; session B (same principal) calls
`job.subscribe { job_id: }`; assert B's `Async::Queue#dequeue`
yields the same `Arcp::Job::Event` instances A's session stream
emits. Then: B calls `cancel` on the subscribe-only handle; assert
`Arcp::Errors::NotAuthorized` raised **client-side without emitting
a wire envelope** — verified by asserting `MemoryTransport#sent` did
not grow. Finally: principal C bypasses the client and sends a raw
`job.cancel` envelope over the wire; assert the runtime replies with
an envelope whose `payload.error.code == "PERMISSION_DENIED"` (per
§7.4 / §12).

### `AgentVersionsSpec` — `spec/unit/agent_versions_spec.rb` (§7.5)

Build `Arcp::Session::AgentInventory` from a `session.welcome`
fixture with `agents: [{ name: 'code-refactor', versions: ['1.0.0',
'2.0.0'], default: '2.0.0' }]`. Assert
`inventory.versions_for('code-refactor') == ['1.0.0', '2.0.0']`.
Submit a job referencing `'code-refactor@2.0.0'`; assert acceptance.
Submit `'code-refactor@9.9.9'`; assert the runtime emits
`job.error` with `payload.error.code == 'AGENT_VERSION_NOT_AVAILABLE'`,
which surfaces in Ruby as `Arcp::Errors::AgentVersionNotAvailable`
(`01-spec-delta.md` §2). Also assert flat-string compat:
`AgentEntry.from_flat('code-refactor')` constructs an entry with
empty `versions` and `default: nil` (Phase 01 §3.3).

### `ResultChunkSpec` — `spec/integration/result_chunk_spec.rb` (§8.4)

Agent fixture emits three `result_chunk` events with `more: true,
true, false`; the terminating `job.result` carries the same
`result_id`. Assertions:

- Assembled bytes (via `Enumerator::Lazy[String]#reduce(:+)`) match
  the original payload exactly.
- `chunk_seq` is monotonic and contiguous (`0, 1, 2`); a fixture
  with `0, 2` is rejected with `Arcp::Errors::ProtocolError`.
- Mixing `result_chunk` events with an inline `job.result.payload`
  on the same job is rejected — the spec §8.4 says "MUST NOT mix";
  the runtime emits `job.error` with code `PROTOCOL_VIOLATION`.

### `LeaseExpiresAtSpec` — `spec/integration/lease_expires_at_spec.rb` (§9.5)

Submit a job with `lease_constraints.expires_at` 60s in the future;
authority op at T+30s succeeds. `FakeClock#advance(120)` past
expiration; authority op at T+120s fails with
`Arcp::Errors::LeaseExpired` (`01-spec-delta.md` §2 row 2). Also
client-side rejection: pass `expires_at: Time.now.iso8601` (no `Z`,
local offset); assert `Arcp::Errors::InvalidRequest` raised before
the envelope is written (`Time#utc?` check from `02-current-audit.md`
§5 row §9.5).

### `CostBudgetSpec` — `spec/integration/cost_budget_spec.rb` (§9.6)

Submit a job with `cost.budget: ["USD:1.00"]`. Agent fixture emits
four `metric { name: 'cost.inference', unit: 'USD', value:
BigDecimal('0.30') }` events — the running total reaches `1.20`,
which exceeds the budget. The 5th op fails with
`Arcp::Errors::BudgetExhausted` and the runtime emits
`tool_result.error.code == 'BUDGET_EXHAUSTED'` (preferred per
`01-spec-delta.md` §2 row 3, so the agent can react). Concurrency
test: fire two `tool.invoke` calls in parallel `Async` tasks, both
metering `0.40`, when remaining budget is `0.50`. Per
`02-current-audit.md` §5 row §9.6, cooperative scheduling makes the
counter safe across awaits **only if no Fiber.yield happens between
read and decrement**; the test asserts the counter never goes
negative by more than one op (so a single overshoot is acceptable;
two overshoots indicates a missing snapshot-then-CAS).

### `CapabilityNegotiationSpec` — `spec/unit/capability_negotiation_spec.rb` (§6.2)

Build `CapabilitySet.new(features: ['heartbeat', 'ack',
'subscribe'].freeze, ...)`. Receive welcome with `features:
['heartbeat', 'subscribe', 'progress'].freeze`. Assert
`local.intersect(remote).features == ['heartbeat',
'subscribe'].freeze`. Then attempt to emit `session.ack` against
that effective set; assert `Arcp::Errors::UnnegotiatedFeature` is
raised by the client send-site **before** any bytes go to
`MemoryTransport#sent`. The guard lives at the
`Arcp::Client#send_envelope` seam (`01-spec-delta.md` §3.4 step 5).

## 4. Pattern-matching test ergonomics

RSpec 3.13 ships no `match_pattern` matcher. Two acceptable
idioms; pick one and document in `spec/support/pattern_matchers.rb`:

**Inline `case ... in` assertion** — preferred for one-off shape
checks:

```
expect {
  case env in { type: 'session.hello', payload: { capabilities: { features: Array } } }
    :ok
  end
}.not_to raise_error
```

`NoMatchingPatternError` becomes a clear RSpec failure.

**Tiny custom matcher** — preferred when the same shape repeats
across a describe block:

```
RSpec::Matchers.define :match_envelope do |pattern|
  match { |env| pattern === env.to_h }
end
expect(env).to match_envelope(type: 'session.hello',
                              payload: hash_including(:capabilities))
```

Rule (`STYLE.md`-adjacent, applied in `spec/support/`): assertions
on envelope shape go through `case ... in`, never `env.dig(:payload,
:capabilities, :features)`. Pattern matching is the production
dispatch idiom (`01-spec-delta.md` operating rules); tests must
exercise the same surface.

## 5. Cancellation hygiene

No `Kernel.sleep` in any spec under `spec/`. Two reasons: the
existing `02-current-audit.md` §7 deployment-model note marks the
runtime as a long-lived `Async`-reactor process — `Kernel.sleep`
blocks the entire reactor, so a test that uses it is testing the
wrong topology. Second: real-time sleeps flake under CI load.

Time advances via `FakeClock#advance(seconds)` against the
`Arcp::Clock.monotonic` seam (§1 row "Time control"). Cooperative
suspension uses `task.sleep(seconds)` (the `Async::Task` instance
method, which suspends only the current fiber and lets the reactor
keep running) **and only inside the WebSocket loopback fixture's
setup** where a small grace is needed for `bind` to land before the
client `connect`s. Anywhere else, use `Async::Condition` to wait
for an event explicitly.

Documented flake patterns to avoid (`spec/support/README.md`):

- `sleep 0.1` to "let the fiber catch up" — replace with
  `Async::Condition#wait`.
- `Timecop.freeze` — doesn't catch
  `Process.clock_gettime(Process::CLOCK_MONOTONIC)`.
- `Thread.new { ... }` in a spec — wrong concurrency model;
  `Async { ... }` instead.

## 6. CI matrix

Two cells. Ruby 3.3 (the floor) and Ruby 3.4 (current stable, what
the gemspec currently pins at `>= 3.4.0` per `02-current-audit.md`
§2 — Phase 03 may relax to 3.3, and the matrix already covers it
either way).

- **3.3** — `Data.define` (3.2+), pattern matching (3.0+), the
  floor for `01-spec-delta.md`. Run with `bundle update
  --conservative --patch` to catch accidental use of 3.4-only
  methods. Bundler `--prefer-lowest` (resolved via Appraisal or a
  dedicated `Gemfile.lock-min` workflow) catches when new code
  reaches for methods only available in newer revs of `async` /
  `async-websocket`.
- **3.4** — current stable; catches the `logger` and `bigdecimal`
  unbundling per `02-current-audit.md` §2 (both now explicit
  `add_dependency`). Coverage report (SimpleCov + branch) runs on
  3.4 only, single cell, to avoid race-conditioning the coverage
  upload across matrix legs.

Two cells. Mutation runs nightly on 3.4 only as a separate workflow
(§1). RuboCop runs on 3.4 only (already gated by
`.rubocop.yml`'s `TargetRubyVersion: 3.4`).

## 7. Coverage floor: 87% lines and branches

`spec/spec_helper.rb` delta — current file is at lines 3–9, this
replaces the `SimpleCov.start` block:

```
SimpleCov.start do
  enable_coverage :branch
  minimum_coverage line: 87, branch: 87
  add_filter '/spec/'
  add_filter '/samples/'
  # CLI moves to `arcp-cli` sub-gem (02-current-audit.md §4.3);
  # its specs live there, not here.
  add_filter '/lib/arcp/cli.rb'
  add_filter '/exe/'
  # Each Arcp::Errors::* subclass is a 3-line Data wrapper; the
  # shared base class in lib/arcp/error.rb is fully exercised, and
  # branch coverage in the subclasses is structurally trivial.
  add_filter '/lib/arcp/errors/' if false  # NOTE: keep enabled; see §2 in plan
end
```

The current `minimum_coverage 94` (line-only) is **lowered** to 87
to match the bootstrap floor; the harder branch requirement
backfills the rigor. Each exclusion's rationale is in a comment so
a reader doesn't have to chase the planning doc.

## 8. Fixtures policy

`spec/fixtures/envelopes/` is regenerated from `draft-arcp-02.1.md`
§13 examples — one file per subsection, naming
`13.1__hello_welcome.json`, `13.2__ack_slow_consumer.json`,
`13.3__list_jobs_subscribe.json`, `13.4__lease_expires_at.json`,
`13.5__budget_enforcement.json`, `13.6__result_chunk_three.json`,
`13.7__agent_versioning.json`. A `rake fixtures:regen` task
re-extracts from the spec markdown's fenced JSON blocks; the regen
is a Phase 6 deliverable since `06-examples.md` already names the
sample directories.

Existing fixtures (any under `spec/fixtures/` keyed to RFC-0001 per
`02-current-audit.md` §8) are **deleted, not edited** — the wire
shape change makes edits more error-prone than starts from the spec
examples. The deletion is part of the v1.0 re-baseline milestone
(`02-current-audit.md` §6 item 5).

`spec-message-types.json` (§2.2) lives at
`spec/fixtures/spec-message-types.json` and lists every wire type
literal in the v1.1 envelope catalog; it's also regenerated from
the spec markdown by the same rake task.

## 9. What not to test

- **Custom logger targets.** The SDK accepts any object implementing
  `#info` / `#warn` / `#error` (`02-current-audit.md` §2 row
  `logger`). Testing the consumer-provided seam is the consumer's
  job; we test that we call those methods, not what they do.
- **Third-party gem internals.** `async`, `async-websocket`,
  `bigdecimal`, `securerandom`. We test our adapter; the gem owner
  tests their gem. Exception: if a gem upgrade breaks a contract we
  rely on, a regression test lives in `spec/regression/`.
- **RuboCop rule outputs.** Lint is a separate CI gate, not an
  RSpec example. A `bundle exec rspec` run does not invoke RuboCop.
- **`dry-cli` argument parsing.** CLI moves to the `arcp-cli` sub-gem
  (`02-current-audit.md` §4.3 + §6 item 9); its specs go with it.
  Core `arcp` gem has zero `lib/arcp/cli.rb` coverage cost.
- **YARD doc rendering.** Phase 08 owns docs build; if YARD fails to
  parse a file that's a CI build break in the docs job, not an
  RSpec failure.

## 10. Spec file inventory (delta vs current 22)

| Layer | New / Renamed | Rationale |
| --- | --- | --- |
| unit | `envelope_spec.rb` (rewrite), `session_spec.rb`, `job_spec.rb`, `lease_spec.rb`, `job_event_spec.rb`, `messages_spec.rb` (rewrite), `session_state_spec.rb`, `job_state_spec.rb`, `subscribe_state_spec.rb`, `agent_versions_spec.rb`, `capability_negotiation_spec.rb`, `ack_spec.rb` | v1.0 re-baseline + v1.1 features per §2.1 + §3 |
| integration | `heartbeat_spec.rb`, `list_jobs_spec.rb`, `subscribe_spec.rb` (rewrite of `subscription_spec.rb`), `result_chunk_spec.rb`, `lease_expires_at_spec.rb`, `cost_budget_spec.rb`, `ack_spec.rb`, `handshake_spec.rb` (rewrite), `job_lifecycle_spec.rb` (rewrite), `cancellation_spec.rb` (rewrite), `resume_spec.rb` (rewrite), `websocket_transport_spec.rb` (rewrite) | §3 + v1.0 re-baseline |
| conformance | `spec/conformance/*` one per `CONFORMANCE.md` row | §2.5 |
| deletion | `extension_unknown_spec.rb`, `interrupt_spec.rb`, `human_input_spec.rb`, `artifact_spec.rb`, `stdio_transport_spec.rb` (partial — keep transport itself), `permission_lease_spec.rb` (replaced by `lease_expires_at_spec.rb`) | RFC-0001 surfaces removed in v1.0 re-baseline per `02-current-audit.md` §6 |

Total target: ~35 spec files, of which ~12 are v1.1-specific.
