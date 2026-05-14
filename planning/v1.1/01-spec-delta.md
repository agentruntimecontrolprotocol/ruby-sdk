# 01 — ARCP v1.1 Spec Delta

Source: `../spec/docs/draft-arcp-02.1.md`. v1.1 is **additive** —
a v1.0 Ruby client speaking to a v1.1 runtime keeps working, and a
v1.1 Ruby client downgrades against a v1.0 runtime via the feature
intersection rule in §6.2.

## 1. Additions table

Columns:

- **§** — spec section.
- **Feature flag** — string sent in
  `session.hello.payload.capabilities.features` and echoed in
  `session.welcome.payload.capabilities.features`. The effective
  set is the intersection (§6.2).
- **Norm** — MUST / SHOULD / MAY for the wire-level requirement on
  the side advertising the feature.
- **Client-side impact** — what the Ruby client implementation must
  gain to use the feature.
- **Runtime-side impact** — what `Arcp::Runtime::Runtime` must gain
  to honor the feature.
- **Compat** — `additive` (existing v1.0 code paths still work
  unchanged when feature absent) or `internal-breaking` (changes a
  v1.0 invariant a v1.1 Ruby runtime must serve a v1.0 client through
  without regression).

| §       | Feature flag        | Message / shape                                                                              | Norm           | Client-side                                                                                             | Runtime-side                                                                                          | Compat                                |
| ------- | ------------------- | -------------------------------------------------------------------------------------------- | -------------- | ------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- | ------------------------------------- |
| §6.2    | (negotiation)       | `capabilities.features: Array[String]` on `session.hello` + `session.welcome`; agents rich object | MUST           | Build feature list from `Feature` constants; intersect with welcome; refuse to emit unnegotiated messages.       | Echo intersection; advertise `agents` rich shape unconditionally; never emit unnegotiated features.   | additive                              |
| §6.4    | `heartbeat`         | `session.ping` / `session.pong`; `welcome.heartbeat_interval_sec`                            | SHOULD send    | `Async::Task` timer per interval; respond to ping within interval; close transport + `HEARTBEAT_LOST` after 2× silence. | Same on runtime side; **MUST NOT** terminate jobs on heartbeat loss — sessions live through the resume window. | additive                              |
| §6.5    | `ack`               | `session.ack { last_processed_seq: Integer }`                                                | client MAY     | Emit ack at most per event or per few-hundred ms — whichever is less frequent.                          | MAY free buffer ≤ ack early; MUST NOT free unacked events even when window elapses unless OOM pressure. | additive                              |
| §6.6    | `list_jobs`         | `session.list_jobs` request → `session.jobs` response, cursored                              | MUST honor     | `Client#list_jobs` returns an `Enumerator::Lazy` that pages on `next_cursor`; filter by status/agent/created_after. | Enforce per-principal visibility; never leak jobs from unrelated principals.                          | additive                              |
| §7.5    | `agent_versions`    | `agent ::= name \| name "@" version`; `welcome.agents[i] = { name:, versions:, default: }`   | MUST resolve   | Accept `name@version`; expose `Session#agents` (`AgentInventory`); pin version to avoid drift.          | Resolve bare name → default; reject unknown with `AGENT_VERSION_NOT_AVAILABLE`; never migrate.        | additive                              |
| §7.6    | `subscribe`         | `job.subscribe { job_id:, from_event_seq?:, history?: }` → `job.subscribed`                  | MUST authorize | Public seam to attach to a job; expose as an `Async::Queue#each` of events, no cancel authority.        | Verify principal can observe; replay buffered events when `history: true`; flow into session stream.  | additive                              |
| §8.2.1  | `progress`          | `kind: "progress" { current:, total?:, units?:, message?: }`                                 | MAY emit       | Decode → frozen `Arcp::Job::Event::Progress` `Data` value; advisory only.                               | Pass-through; protocol takes no action.                                                               | additive                              |
| §8.4    | `result_chunk`      | `kind: "result_chunk" { result_id:, chunk_seq:, data:, encoding:, more: }` → `job.result.result_id` | MUST NOT mix | `Enumerator::Lazy[String]` decoded by `encoding`; assert monotonic `chunk_seq`.                          | Allocate `result_id` when streaming begins; terminate with `job.result.result_id`; reject inline-mix. | additive                              |
| §9.5    | `lease_expires_at`  | `job.submit.payload.lease_constraints.expires_at`                                            | MUST enforce   | Send ISO-8601 UTC `Z`; reject local-offset timestamps client-side before submit (`Time#utc?`).          | Evaluate on every authority op; emit `LEASE_EXPIRED` (retryable: false); MAY pre-terminate expired.   | additive                              |
| §9.6    | `cost.budget`       | `cost.budget: ["CCY:amount", …]`; `metric { name: cost.*, value:, unit: }` decrements        | MUST enforce   | Encode amount strings via `BigDecimal`; surface budget state via opt-in `cost.budget.remaining` metrics. | Per-currency counter; check before every authority op; `BUDGET_EXHAUSTED` (retryable: false).         | additive                              |
| §9.4    | (delegation rules)  | Child `cost.budget` ≤ parent remaining; child `expires_at` ≤ parent `expires_at`             | MUST           | When Ruby code is a delegating agent, compute the bounded child lease.                                  | Enforce subsetting on `delegate` envelope; reject violators with `LEASE_SUBSET_VIOLATION`.            | additive                              |
| §11     | (trace attrs)       | `arcp.lease.expires_at`, `arcp.budget.remaining` span attributes                             | SHOULD         | OTEL middleware adds both attributes when the lease carries them.                                       | Same on runtime side.                                                                                 | additive                              |
| §12     | (error codes)       | `AGENT_VERSION_NOT_AVAILABLE`, `LEASE_EXPIRED`, `BUDGET_EXHAUSTED`                            | MUST           | Three new `final` subclasses of `Arcp::Error`; `#code` returns the spec string.                         | Emit with `retryable: false`; surface via `tool_result` for budget so the agent can recover.          | internal-breaking: error enum grows   |

## 2. Three new error codes (§12)

All three appear in `payload.error.code` and map to a dedicated
subclass of `Arcp::Error`. The current `lib/arcp/error_code.rb` is a
21-entry gRPC-style table (Phase 02 §3.4 walks through it); these
v1.1 codes land alongside it, and Phase 02 + Phase 10 schedule the
broader gRPC-vs-spec retirement as part of the v1.0 re-baseline.

| Spec code                     | Ruby class (target)                       | Source seam                                                                                                                | `retryable` | Notes                                                                              |
| ----------------------------- | ----------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- | ----------- | ---------------------------------------------------------------------------------- |
| `AGENT_VERSION_NOT_AVAILABLE` | `Arcp::Errors::AgentVersionNotAvailable`  | `job.accepted` / `job.error` when `name@version` requested but version not registered (§7.5).                              | false       | Distinct from `AGENT_NOT_AVAILABLE`: the name resolved but the pinned version did not. |
| `LEASE_EXPIRED`               | `Arcp::Errors::LeaseExpired`              | `tool_result` (per op) or `job.error` (`final_status: "error"`) when an authority op runs at or after `expires_at` (§9.5). | false       | Currently present as a constant in `lib/arcp/error_code.rb:23` but has no enforcement path. v1.1 turns it from "string in a table" into a wired-up error. |
| `BUDGET_EXHAUSTED`            | `Arcp::Errors::BudgetExhausted`           | `tool_result` (preferred — agent can react) or `job.error` if runtime treats exhaustion as fatal (§9.6).                   | false       | Counters are per-currency; one currency hitting zero blocks all authority ops.     |

Each Ruby target class is a small subclass — `Arcp::Error` already
exists at `lib/arcp/error.rb` — with:

- A `CODE` constant returning the spec wire string.
- A `#code` reader returning `CODE` (does NOT override
  `Exception#code` since `Exception` has no such method; safe to add).
- Frozen-string-literal `code:`, `message:`, optional `details:` and
  `retryable:` keyword arguments at construction; the existing
  `Arcp::Error` pattern (lib/arcp/error.rb) is the shape to mirror.

The existing `ErrorCode::ALL` constant in `lib/arcp/error_code.rb`
gets three new entries; the gRPC retirement in §3.4 of Phase 02 is a
separate concern.

## 3. Capability negotiation (§6.2)

Three artifacts drive every downstream phase:

### 3.1. `Feature` constants module

```
module Arcp
  module Session
    module Feature
      HEARTBEAT         = 'heartbeat'
      ACK               = 'ack'
      LIST_JOBS         = 'list_jobs'
      SUBSCRIBE         = 'subscribe'
      LEASE_EXPIRES_AT  = 'lease_expires_at'
      COST_BUDGET       = 'cost.budget'
      PROGRESS          = 'progress'
      RESULT_CHUNK      = 'result_chunk'
      AGENT_VERSIONS    = 'agent_versions'

      ALL = [
        HEARTBEAT, ACK, LIST_JOBS, SUBSCRIBE, LEASE_EXPIRES_AT,
        COST_BUDGET, PROGRESS, RESULT_CHUNK, AGENT_VERSIONS
      ].freeze
    end
  end
end
```

Closed by convention via `ALL.freeze`. A v1.2 feature on the wire is
**dropped** at decode rather than handed up the stack — forward-compat
for the runtime is "ignore what you don't know," but the constants
table never silently grows. Phase 04 chooses between a constants
module and a Sorbet `T::Enum` / `dry-types` constant; the wire shape
is identical either way.

### 3.2. `CapabilitySet` value object

```
module Arcp
  module Session
    CapabilitySet = Data.define(:features, :encodings, :agents) do
      def intersect(other) = self.class.new(
        features:  (features & other.features).freeze,
        encodings: (encodings & other.encodings).freeze,
        agents:    agents,
      )
      def supports?(feature) = features.include?(feature)
    end
  end
end
```

`Data.define` (Ruby 3.2+, hard-floor 3.3 per STYLE.md but the gemspec
pins `>= 3.4.0`) gives a frozen, value-comparable, kw-constructable
struct in one line. Intersection lives on the value object, not on
`Session`, so it can be tested without I/O. Every place the SDK
considers emitting a feature-gated message calls
`session.capabilities.supports?(Feature::HEARTBEAT)`.

### 3.3. `AgentInventory` rich shape (§7.5)

```
module Arcp
  module Session
    AgentEntry = Data.define(:name, :versions, :default) do
      def self.from_hash(h) = new(
        name: h.fetch('name'),
        versions: Array(h['versions']).freeze,
        default: h['default'],
      )
      def self.from_flat(name) = new(name:, versions: [].freeze, default: nil)
    end

    AgentInventory = Data.define(:entries) do
      def default_for(name) = entries.find { _1.name == name }&.default
      def versions_for(name) = entries.find { _1.name == name }&.versions || [].freeze
    end
  end
end
```

`from_flat` is the v1.0 compat path: a v1.0 runtime returning
`agents: ["code-refactor", …]` decodes into entries with empty
`versions` and `default: nil`. Any v1.1 client code that then attempts
`name@version` against such an inventory fails fast with a typed
`AgentVersionNotAvailable` rather than crashing decode.

### 3.4. Negotiation lifecycle

1. Ruby client builds `CapabilitySet` from `Feature::ALL`.
2. Encodes into `session.hello.payload.capabilities`.
3. Decodes `session.welcome.payload.capabilities`; constructs the
   runtime's `CapabilitySet`.
4. Stores `effective = local.intersect(remote)` on the `Session`
   `Data` (immutable post-welcome).
5. Every feature-gated send-site calls
   `session.capabilities.supports?(Feature::ACK)`; if false, raise
   `Arcp::Errors::UnnegotiatedFeature` — library-internal, never
   reaches the wire. Phase 04 owns where in the stack the guard
   sits.

## 4. Scope boundary — what v1.1 is NOT

These are explicitly deferred per spec "Not in v1.1":

- Job pause / unpause.
- Job priority and scheduling hints.
- Federation across runtimes.
- Streaming-token surface for LLM outputs (separate from
  `result_chunk`, which is final-result streaming).

Do not let Phase 04 architecture pre-bake hooks for any of these. A
future `Feature::JOB_PAUSE` constant lands when v1.2 ships, with one
new `case ... in` arm in the dispatcher and one new message class.
Pattern-matching against a closed feature set is the extension
mechanism — speculative generalization is banned per the bootstrap
anti-slop rules.

## 5. Reference index for downstream phases

| Phase                 | Spec § to keep open                                            |
| --------------------- | -------------------------------------------------------------- |
| 03 libraries          | §4 (transport), §5 (wire format)                               |
| 04 architecture       | §6.2, §6.4, §6.5, §7.5, §7.6, §8.4, §9.5, §9.6, §11, §12       |
| 05 middleware         | §4 (WS), §6.4 (heartbeat), §11 (trace)                         |
| 06 examples           | §13.1–§13.7 (one example per v1.1 surface, already worked out) |
| 07 tests              | §6.4–§6.6, §7.5–§7.6, §8.4, §9.5–§9.6, §12                     |
| 08 docs               | §1–§3, §6.2, §12                                               |
| 09 diagrams           | §6.4 ack/heartbeat, §7.6 subscribe FSM, §8.4 chunk sequence    |
