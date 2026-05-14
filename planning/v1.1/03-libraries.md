# 03 — Libraries

One pick per concern. Each pick rules a runner-up out by name. Every
"why" cites a spec §, an SDK path, a Ruby idiom (`Data.define`,
`case ... in`, `Async { }`, `Enumerator::Lazy`, RBS sig), or a named
gem. The 16-row gemspec diff at the bottom is the contract.

Ruby floor stays at 3.4 (matches current `arcp.gemspec:20` and
`.rubocop.yml:6` `TargetRubyVersion: 3.4`). Relaxing to 3.3 buys
nothing — every Ruby 3.4 path in `lib/arcp/` is covered by 3.3 + 3.4
features already (`Data.define`, `case ... in`, `SecureRandom.uuid_v7`,
`it`-block syntax).

## 1. JSON — stdlib `json` (default), `oj` as opt-in adapter

**Pick:** stdlib `json`.

**Why over `oj`:** `oj` is faster but forcing it onto every consumer
violates the SDK's "no surprise dependencies" rule — `oj` patches
`JSON.dump`/`JSON.parse` semantics if loaded with `Oj.mimic_JSON`,
and silently changes precision for `BigDecimal` round-trips, which
collides with §9.6 (`cost.budget` arithmetic — see pick 14 below).
The current `lib/arcp/json.rb` is a six-line wrapper around stdlib
`JSON.generate` / `JSON.parse`; v1.1 keeps that seam and adds an
optional `Arcp::Serializer.backend = :oj` setter that consumers opt
into in their own app boot. Default `require 'arcp'` never loads
`oj`.

**gem + last release:** stdlib `json` (3.2.x, bundled with Ruby
3.4); `oj` ~3.16 as an opt-in adapter, not declared in `arcp.gemspec`.

## 2. WebSocket client — `async-websocket`

**Pick:** `async-websocket` (socketry).

**Why over `faye-websocket`:** `faye-websocket` is EventMachine-based;
EventMachine is a thread-reactor that does not cooperate with the
Fiber scheduler the rest of the SDK runs on (`async ~> 2.0` per
`arcp.gemspec:43`). Mixing the two means two reactor loops in one
process — `lib/arcp/transport/web_socket_transport.rb` (current) is
already on `async-websocket`, so this pick is "confirm the
incumbent." Cancellation propagates as `Async::Stop` through the
read loop — Phase 02 §5 row §7.6 calls out that the subscribe
attach path needs `Async::Task#stop` propagation, which
`async-websocket` already honors.

**gem + last release:** `async-websocket` ~0.30 (confirmed
incumbent — `arcp.gemspec:44`).

## 3. WebSocket server — `async-websocket` over Falcon

**Pick:** `async-websocket`'s `Async::WebSocket::Adapters::Rack`
hosted by Falcon (`falcon` Rack server).

**Why over Puma+hijack+a-WS-gem:** Puma's Rack hijack works but Puma
threads do not suspend on Fiber awaits — a `job.subscribe` listener
(§7.6) and a `session.ping`/`session.pong` timer (§6.4) both live
for the duration of a session, and Puma's per-request thread model
either ties up a worker thread for the session lifetime or kills it
mid-`Async::Task`. Phase 02 §7 calls this out as a deployment-model
constraint. `arcp-falcon` (Phase 05 sub-gem) is the canonical
runtime host; `arcp-rack` exists for completeness but documents the
Puma caveat. Falcon itself is **not** declared in the core
`arcp.gemspec` — it is a host concern, declared by the consumer (or
by `arcp-falcon`).

**gem + last release:** `async-websocket` ~0.30; consumer adds
`falcon` ~0.49 in its own Gemfile.

## 4. HTTP — `async-http`

**Pick:** `async-http`.

**Why over `faraday`:** `faraday` is adapter-pluggable but the
default `net/http` adapter blocks the reactor — every outbound
agent-side HTTP call from inside an `Async { }` block would stall
peer fibers. `async-http` shares the same reactor and `Async::Task`
cancellation model as `async-websocket` (pick 2). The SDK currently
makes no outbound HTTP calls in `lib/arcp/`; this dep lands when
v1.1's §7.6 subscribe needs to fetch resume history from a remote
runtime, and lands once with the right reactor semantics rather
than via a `faraday` rewrite later. Keep it declared in core
because `Arcp::Client` will need it for §8.4 result-chunk fetch
when the runtime offers `result_chunk` over HTTP fallback.

**gem + last release:** `async-http` ~0.86.

## 5. Concurrency — `async`

**Pick:** `async` (Fiber-scheduler-based, `arcp.gemspec:43`).

**Why over `concurrent-ruby` threads on I/O paths:**
`concurrent-ruby` thread pools serialize the Fiber scheduler — a
read from `Async::Queue` inside a `concurrent-ruby` `Future` blocks
the worker thread (Fibers do not migrate across threads), defeating
the §7.6 cross-session subscribe goal where one fiber relays events
from a `JobManager` queue to N subscriber transports.

**Why over `EventMachine`:** EventMachine's reactor is a separate
event loop that cannot share a stack with `async-websocket` /
`async-http` (picks 2 + 4). Two reactors in one process is the
classic Ruby footgun. `concurrent-ruby` stays useful for **pure CPU**
work (e.g. a `Concurrent::AtomicReference` for the `cost.budget`
counter §9.6 — see pick 6 below — when read by metrics middleware
from outside the reactor).

**gem + last release:** `async` ~2.20.

## 6. Validation / types — plain `Data.define` + `case ... in`

**Pick:** `Data.define` (Ruby 3.2+) with pattern matching for
dispatch; **no** `dry-validation` / `dry-struct`; **no** Sorbet
`T::Struct` for value objects.

**Why over `dry-validation` + `dry-struct`:** the `dry-rb` stack is
designed for "validate untrusted input arriving at a controller."
This SDK's envelopes (`lib/arcp/envelope.rb`) and message payloads
arrive over `async-websocket` as already-parsed JSON; the validation
shape is "this Hash matches the v1.1 schema for `session.hello`."
`case env in { type: "session.hello", payload: { capabilities: { features: Array => feats } } }`
expresses that in one line of stdlib Ruby; `dry-validation` adds a
Reform-style DSL the SDK does not need. Phase 02 §4.1 records that
`lib/arcp/envelope.rb`, `lib/arcp/ids.rb`, and the 14 message
payload modules already use `Data.define` heavily — Phase 02 §3.4 of
01-spec-delta builds `CapabilitySet` and `AgentInventory` as
`Data.define`s. Sticking with `Data.define` means zero new dep and
one idiom across the codebase.

**Why over Sorbet `T::Struct`:** `T::Struct` requires `sorbet-runtime`
at runtime — a non-trivial gem that monkey-patches Ruby's method
table. `Data.define` ships in stdlib. See pick 11 for the type-checker
decision; even when type-checking is added, `Data.define` + RBS sigs
beats `T::Struct` for value objects because RBS sigs are external
files that do not run at request time.

**Idiom contract for Phase 04:** every wire-message payload is a
`Data.define` with frozen kwargs; every dispatch site uses
`case ... in` — never a Hash lookup table.

**gem + last release:** none — stdlib `Data.define`.

## 7. Reject `json_schemer`

**Why:** Phase 02 §2 flags `json_schemer ~> 2.0` (`arcp.gemspec:46`)
as vestigial — likely a leftover from RFC-0001 capability discovery.
v1.0/v1.1 wire validation does not require JSON Schema at runtime;
the spec defines shapes in §5.1 and §6–§10, and the Ruby way to
enforce those is `Data.define`'s kw-only constructor (which raises
`ArgumentError` on missing keys) plus `case ... in` pattern matching
on decode. A `case env.payload in { capabilities: { features: Array
=> feats } }` is both validation and destructuring in one pass —
`json_schemer` would just produce a list of error paths the SDK has
to translate back into `Arcp::Error` subclasses anyway.

**Action:** delete from `arcp.gemspec`. Phase 04 owns the migration —
any current call site is wrong against v1.0 + v1.1 wire shape and
gets rewritten when the envelope (Phase 02 §6.1) flips to 8 fields.

## 8. Logging — stdlib `Logger`

**Pick:** stdlib `Logger` (already declared as `logger ~> 1.6` per
`arcp.gemspec:48`, kept because Ruby 3.4 unbundled it).

**Why over `semantic_logger`:** `semantic_logger` is great but it is
a logging *destination*, not a logging *interface*. The SDK's rule
is "accept any object responding to `#info`/`#warn`/`#error` as the
`logger:` kwarg on `Arcp::Client.new` / `Arcp::Runtime.new`." That
is duck-typed; a consumer plugs in `Rails.logger`,
`SemanticLogger['Arcp']`, or `Ougai` without the SDK declaring any
of them. The SDK's own default logger is `Logger.new($stderr)` at
`WARN`.

**Don't:** invent an `Arcp::Logger` wrapper interface; that is the
"power-of-three" overgrowth the Phase 02 audit pre-emptively warns
against in §3 by quoting STYLE.md's "no `extend self` modules that
hide state."

**gem + last release:** `logger` ~1.6 (gemspec already declares it,
correct for 3.4).

## 9. IDs — `SecureRandom.uuid_v7` for envelopes; keep ULID for
sortable IDs

**Pick:** `SecureRandom.uuid_v7` (Ruby 3.3+, stdlib) for `Envelope#id`
and any monotonic-ordered ID where readers index by time. **Reject**
the `ulid` gem.

**Why over the `ulid` gem:** `lib/arcp/ids.rb:14` already implements
a Crockford-base32 ULID in 16 lines of stdlib Ruby
(`SecureRandom.random_number(1 << 80)` + millisecond timestamp). The
external `ulid` gem (~1.4) adds ~1500 LOC plus a `MonotonicGenerator`
that the SDK does not need — `Async`-scheduled message generation
happens in one Fiber per session and the millisecond resolution of
the current hand-rolled ULID is sufficient because the wire format
also carries `event_seq` per §5.1 for absolute ordering.

**Why UUIDv7 for envelope IDs:** Ruby 3.3 added
`SecureRandom.uuid_v7`. UUIDv7 is sortable by generation time (like
ULID) but renders as a 36-char hyphenated string interop tools
already grok. `Arcp::MessageId` keeps the `msg_<ulid>` prefix
format for log-grep ergonomics in
`lib/arcp/ids.rb:42` — that is a typed ID, not a wire envelope id.
v1.1 work picks one and applies it consistently — Phase 04 makes the
final call, but the recommendation here is: envelope `id` field uses
`SecureRandom.uuid_v7` (no prefix, matches §5.1's free-form `id`),
and the internal typed `Arcp::MessageId` keeps the ULID + prefix
shape for human readability in the existing `Arcp::IdBuilder` table
(`lib/arcp/ids.rb:42-51`).

**gem + last release:** stdlib `securerandom` (Ruby 3.4 bundled);
no `ulid` gem.

## 10. Tracing — `opentelemetry-api` (API only)

**Pick:** `opentelemetry-api`, declared in `arcp.gemspec` as a
runtime dep. Consumer wires the SDK + exporter (e.g.
`opentelemetry-sdk` + `opentelemetry-exporter-otlp`) themselves.

**Why API-only:** the SDK emits spans and sets attributes
(`arcp.lease.expires_at`, `arcp.budget.remaining` per §11); it does
not own batching, sampling, or exporter config — those are deploy
concerns. Declaring `opentelemetry-sdk` in core would force every
consumer onto our exporter choice. Same pattern as the TS SDK's
`@opentelemetry/api` peer dep.

**Implementation seam:** `lib/arcp/trace.rb` (current — Fiber-local
context) wraps `OpenTelemetry.tracer_provider.tracer('arcp')` and
exposes `Arcp::Trace.in_span(name) { |span| ... }`. The middleware
(`arcp-otel` per Phase 05) attaches the W3C `traceparent` to
`Envelope#trace_id` and adds the v1.1 attributes.

**gem + last release:** `opentelemetry-api` ~1.5.

## 11. Type check — RBS + Steep (write sigs as we go)

**Pick:** RBS + Steep. Hand-write `sig/arcp/*.rbs` for the public
surface (`Arcp::Client`, `Arcp::Runtime`, `Arcp::Envelope`, all
`Arcp::Errors::*`, the `Arcp::Session::Feature` / `CapabilitySet` /
`AgentInventory` from 01 §3, the `Arcp::Lease::CostBudget` from
§9.6). Internal modules can stay unsigned.

**Why over Sorbet:** Sorbet's runtime (`sorbet-runtime`) inserts
type checks at every annotated method call — that is a real cost on
`Async`-scheduled hot paths where the message dispatcher calls
`case env in ...` millions of times per long-running runtime
process. RBS is external (`sig/**/*.rbs`); Steep runs in CI; runtime
overhead is zero. `arcp.gemspec:30` already declares `sig/**/*.rbs`
in the files glob — the directory is **empty**, per Phase 02 §2.
v1.1 is the moment to start writing those sigs.

**Why not "skip type-check in v1.1":** the public API surface is
exactly the kind of thing RBS catches — kwarg drift on
`Arcp::Client#submit_job` between v1.0 and v1.1 would otherwise be
caught only by RSpec. RBS catches it at lint time. Phase 07 gates
`bundle exec steep check` in CI alongside `rspec` + `rubocop`.

**gem + last release:** `rbs` ~3.6 (bundled stdlib gem since
3.3 — but explicit dev dep pins it); `steep` ~1.9 (dev only).

## 12. Testing — RSpec + SimpleCov branch + `async-rspec`; skip
`mutant` for v1.1

**Pick (test framework):** RSpec (already `rspec ~> 3.13` in
`Gemfile:11`).

**Pick (coverage):** SimpleCov with `enable_coverage :branch` — the
current `Gemfile:15` declares `simplecov ~> 0.22` but Phase 02 §3
flags that branch coverage is **not** enabled. Phase 07 owns the
config; this plan locks the choice.

**Pick (Fiber-aware specs):** `async-rspec`. **Add** to Gemfile (it
is not currently there). The §6.4 heartbeat timer, §7.6 subscribe
relay, and §8.4 result_chunk streaming all need `Sync { ... }` /
`Async { ... }` blocks in specs that propagate `Async::Stop`
correctly — `async-rspec` provides the matchers and the
`describe ... include_context Async::RSpec::Reactor` shape.

**Pick (mutation):** **skip** for v1.1. `mutant` is excellent but
nightly-CI-only and pricey to set up; the SDK is wire-protocol-shaped
where mutation testing flags many "indistinguishable" mutations
because two `case ... in` arms differ by string literal. The
87%-line-and-branch SimpleCov floor (Phase 02 §3) plus an integration
suite keyed to `CONFORMANCE.md` is the v1.1 coverage contract. Add
`mutant` in v1.2 if the conformance suite proves insufficient.

**gem + last release:** `rspec` ~3.13; `simplecov` ~0.22;
`async-rspec` ~1.17.

## 13. Lint / format — RuboCop (keep incumbent)

**Pick:** RuboCop with the three existing plugins
(`rubocop-performance`, `rubocop-rake`, `rubocop-rspec` per
`Gemfile:12-14`).

**Why over `standardrb`:** `standardrb` is RuboCop with a frozen
config; the SDK's `STYLE.md` documents intentional deviations
(`Layout/LineLength: 110`, `Metrics/MethodLength: 40`,
`Metrics/ClassLength: 400`, `Metrics/ModuleLength: 400`) and a
`REFACTOR_BACKLOG.md` for outliers. Adopting `standardrb` either
forces those deviations back to defaults (regression against
`STYLE.md`) or layers `standardrb` + an override config, which is
strictly worse than the current RuboCop setup. Phase 02 §3 also
records that lefthook already wires `rubocop --force-exclusion` as
pre-commit; switching changes the lefthook contract for no win.

**gem + last release:** `rubocop` ~1.68 with `rubocop-performance`
~1.22, `rubocop-rake` ~0.6, `rubocop-rspec` ~3.2.

## 14. Decimal math — `bigdecimal` runtime dep (NEW)

**Pick:** add `bigdecimal` as a runtime `add_dependency` in
`arcp.gemspec`.

**Why:** Ruby 3.4 unbundled `bigdecimal` from default stdlib —
Phase 02 §2 explicitly flags this. §9.6 of v1.1 says
`cost.budget: ["CCY:amount", …]` and metric decrement is by
`BigDecimal(amount_string)` — `Float` arithmetic introduces
representation drift after a few hundred decrement ops, which is the
exact "spend the entire budget by accumulating rounding error" bug
the v1.1 spec retires. The cost-budget counter inside
`Arcp::Lease::CostBudget` (Phase 02 §5 row §9.6) holds a per-currency
`BigDecimal`; arithmetic uses `BigDecimal#-` / `#+`; comparison uses
`#<=` against `BigDecimal("0")`.

**Not Fiber-safe by default — note for Phase 07:** the read-decrement-
write triple is atomic under cooperative Fiber scheduling **only if
no `await` happens between read and write**. Phase 07 §test plan
explicitly covers this; the implementation in Phase 04 keeps the
critical section straight-line code with no `Async` yields.

**gem + last release:** `bigdecimal` ~3.1 (or ~3.2 — gemspec pin
`~> 3.1`).

## 15. Build — Bundler 2.x

**Pick:** Bundler 2.x (no alternative for a `.gemspec`-based gem).
Release happens via `bundle exec rake build` + `gem push`. No
`rubygems-tasks`, no `bundler-release`; `Rakefile` exposes `build`
+ `release` from `Bundler::GemTasks` (the Ruby standard).

**gem + last release:** `bundler` ~2.5.

## 16. Reject: `dry-cli`, `jwt` in core

**`dry-cli`:** Phase 02 §6.9 schedules `lib/arcp/cli.rb` (currently
monolithic dry-cli commands) for extraction to an `arcp-cli`
sub-gem. The `dry-cli ~> 1.0` dep at `arcp.gemspec:45` moves with
it. The `exe/arcp` executable name stays — it ships from the
`arcp-cli` gem instead of `arcp`. Core consumers who only want the
library (`gem 'arcp'`) no longer get `dry-cli` and its
`concurrent-ruby` transitive dep pulled in.

**`jwt`:** Phase 02 §6.11 schedules `lib/arcp/auth/jwt.rb` for
extraction to an `arcp-auth-jwt` sub-gem. v1.0 §6.1 only requires
bearer tokens; JWT is an opt-in scheme. The `jwt ~> 2.0` dep at
`arcp.gemspec:47` moves with it. `Arcp::Auth::BearerAuth` stays in
core. The `AuthScheme` interface stays in core so `arcp-auth-jwt`
plugs in.

## 17. Diff vs current `arcp.gemspec` (16 rows)

| #  | Line in current gemspec | Dep                  | v1.1 action       | Reason (§ or pick)                                                |
| -- | ----------------------- | -------------------- | ----------------- | ----------------------------------------------------------------- |
| 1  | `:43`                   | `async ~> 2.0`       | keep              | pick 5 — Fiber scheduler stays the I/O model                      |
| 2  | `:44`                   | `async-websocket ~> 0.30` | keep         | pick 2 — incumbent WS client; pick 3 — server via Falcon          |
| 3  | `:45`                   | `dry-cli ~> 1.0`     | **drop from core**, move to `arcp-cli`     | pick 16 / Phase 02 §6.9        |
| 4  | `:46`                   | `json_schemer ~> 2.0` | **drop**         | pick 7 — `Data.define` + `case ... in` covers wire validation     |
| 5  | `:47`                   | `jwt ~> 2.0`         | **drop from core**, move to `arcp-auth-jwt` | pick 16 / Phase 02 §6.11      |
| 6  | `:48`                   | `logger ~> 1.6`      | keep              | pick 8 — Ruby 3.4 unbundled, explicit dep is correct              |
| 7  | `:49`                   | `sqlite3 ~> 2.0`     | keep (runtime-side only; document) | Phase 02 §2 — `lib/arcp/store/event_log.rb` resume buffer |
| 8  | (new)                   | `async-http ~> 0.86` | **add**           | pick 4 — Fiber-aware HTTP for §8.4 fallback + future outbound    |
| 9  | (new)                   | `opentelemetry-api ~> 1.5` | **add**     | pick 10 — §11 trace attrs; API-only (no SDK / exporter)           |
| 10 | (new)                   | `bigdecimal ~> 3.1`  | **add**           | pick 14 — Ruby 3.4 unbundled; §9.6 cost-budget arithmetic         |
| 11 | `Gemfile:11`            | `rspec ~> 3.13` (dev) | keep             | pick 12 — incumbent                                               |
| 12 | (new dev)               | `async-rspec ~> 1.17` (dev) | **add**     | pick 12 — Fiber-aware specs for §6.4 / §7.6 / §8.4                |
| 13 | `Gemfile:15`            | `simplecov ~> 0.22` (dev) | keep + enable branch coverage | pick 12 — Phase 07 wires `enable_coverage :branch` |
| 14 | (new dev)               | `rbs ~> 3.6` (dev)   | **add**           | pick 11 — RBS sigs in `sig/` (currently empty, glob already in spec.files) |
| 15 | (new dev)               | `steep ~> 1.9` (dev) | **add**           | pick 11 — `bundle exec steep check` gates public surface          |
| 16 | `Gemfile:11-14`         | rubocop + 3 plugins (dev) | keep         | pick 13 — STYLE.md deviations argue against `standardrb`          |

Net change: `-3` runtime deps removed from core (`dry-cli`,
`json_schemer`, `jwt`), `+3` added (`async-http`,
`opentelemetry-api`, `bigdecimal`); `+3` dev deps added
(`async-rspec`, `rbs`, `steep`). Two sub-gems gain owned deps
(`arcp-cli` owns `dry-cli`; `arcp-auth-jwt` owns `jwt`). `sig/`
directory stops being an empty glob target and starts holding RBS
files for the public surface listed in pick 11.
