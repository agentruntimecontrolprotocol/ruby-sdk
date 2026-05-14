# 10 — Synthesis: ARCP Ruby SDK v1.1 Migration

Inputs: `01-spec-delta.md` through `09-diagrams.md`. This file does
not restate them — it integrates, resolves contradictions, and
orders the work into PR-sized milestones with files + spec §.

---

## 1. Executive summary

The headline: **this is not a v1.1 patch, it is a v1.0 re-baseline
plus a v1.1 additive layer, in that order.** Phase 02 §1 surfaced
that the current `lib/arcp/` implements `../spec/docs/draft-arcp-01.md`
(RFC-0001), not `draft-arcp-02.md` (v1.0). The wire taxonomy
(58 wire-type literals), the 19-field envelope, the 21-code
gRPC-shaped error table, and the session/job lifecycle envelopes
all diverge from the v1.0 (draft-02) wire that this SDK does not
yet speak.

Three structural moves drive every other decision:

1. **Re-baseline the wire to `draft-arcp-02.md` (v1.0).** This means
   reducing `Arcp::Envelope` from 19 fields (`lib/arcp/envelope.rb`)
   to the §5.1 set of 8, flipping `Arcp::PROTOCOL_VERSION` from
   `'1.0'` to the wire literal `'1'`, unifying the `log`/`metric`/
   `event.emit`/`trace.span`/`tool.*`/`stream.*` envelopes into
   `job.event { kind, body }`, and collapsing the 21 gRPC-style codes
   in `lib/arcp/error_code.rb` to 12 v1.0 codes. `02-current-audit.md`
   §6 enumerates the 11 items.
2. **Add the v1.1 surface.** Nine features behind a closed
   `Arcp::Session::Feature` constants module (`01-spec-delta.md`
   §3.1), three new error codes
   (`AGENT_VERSION_NOT_AVAILABLE`, `LEASE_EXPIRED`,
   `BUDGET_EXHAUSTED`), capability negotiation by intersection
   (`01-spec-delta.md` §3.4). Per-feature client + runtime work,
   tested behind a conformance harness.
3. **Split the deployment story honestly.** `arcp` (core) becomes
   `dry-cli`-free and `jwt`-free; the CLI moves to `arcp-cli`, JWT
   auth to `arcp-auth-jwt`, and four host-adapter gems land
   (`arcp-rack`, `arcp-falcon`, `arcp-rails`, `arcp-otel`).
   `04-architecture.md` §1.2 + Phase 05 own the gem layout;
   `02-current-audit.md` §7 and the deployment guide (Phase 08) call
   out daemon-or-Falcon-not-per-request-Puma as a hard rule.

The plan reaches v1.1 in **six PR-sized milestones** (§5 below). The
first three are the v1.0 re-baseline; only milestones 4–6 add v1.1
surface. Coverage floor (87% line+branch via SimpleCov branch
coverage, Phase 07), RuboCop max with `phpstan-strict`-equivalent
plugins (kept; `standardrb` rejected, Phase 03 §13), RBS sigs
written for the public surface and gated by Steep (Phase 03 §11),
and `bundle exec rake conformance` (Phase 07 §2.5 equivalent) are
the gates each milestone clears.

---

## 2. Contradictions resolved

Resolved between phases so milestone work doesn't trip over
conflicting recommendations.

### 2.1. Closed `MESSAGE_TYPES` constants vs `MessageTypeRegistry`

- `lib/arcp/message_type.rb` currently ships a runtime hash registry
  (`MessageTypeRegistry.register(wire_name, payload_class)`).
- `04-architecture.md` §2 replaces this with a frozen
  `MESSAGE_TYPES` constants module + closed `case ... in` dispatch.
- `06-examples.md` row 8 (`vendor-extensions`) explicitly relies on
  unknown `kind`s flowing through a `case ... in {kind: String => k}`
  arm — not a registry.

**Resolution:** Phase 04 wins. The runtime registry is retired in
milestone 2 (wire re-baseline). Vendor extensions land via a
catch-all `else` arm in the `case ... in` dispatcher, not via
registering at runtime. The `lib/arcp/extensions.rb` namespace
registry stays — that's a separate concern (extension namespace
allocation), not a payload-class registry.

### 2.2. Ruby floor — 3.3 or 3.4?

- BOOTSTRAP.md says "Ruby 3.3+" floor.
- `arcp.gemspec:20` pins `>= 3.4.0`.
- `02-current-audit.md` §2 flagged 3.4 as accidentally tight.
- `03-libraries.md` §0 **keeps** 3.4, arguing every 3.3 path is also
  3.4-clean.
- `07-tests.md` §6 tests on 3.3 + 3.4 (matrix).

**Resolution:** Floor is **3.3**, matching BOOTSTRAP and the CI
matrix. `arcp.gemspec` change is part of milestone 1. Rationale: a
3.4-only floor would orphan macOS/Linux distros still shipping 3.3
(Debian stable, Ubuntu LTS) for no language-feature win — every
construct in `lib/arcp/` (`Data.define`, `case ... in`,
`SecureRandom.uuid_v7`, endless methods) is 3.3-clean. Phase 03 is
amended.

### 2.3. `oj` opt-in adapter

- `03-libraries.md` §1 picks stdlib `json` and adds an opt-in
  `Arcp::Serializer.backend = :oj` setter.
- `04-architecture.md` does not mention an `oj` switch.

**Resolution:** Phase 03 wins. The opt-in switch is part of
`Arcp::Serializer` (renamed from `Arcp::Json` per
`02-current-audit.md` §4.3). The default never loads `oj`. Phase 04
is amended implicitly: `Arcp::Serializer.backend=` is a public
class-method API surface; document it under `docs/reference/extensions-config.md`
(Phase 08 §1).

### 2.4. RBS / Sorbet — written for v1.1 or deferred?

- `03-libraries.md` §11 **adds** RBS + Steep as dev deps; sigs
  written in milestone 1 for the public surface (the empty
  `sig/**/*.rbs` glob in `arcp.gemspec` files-block stops being
  decorative).
- `04-architecture.md` §6 lists "RBS sigs at the public seam" as a
  hard rule.

**Resolution:** Sigs land **incrementally per milestone**, not all
at once in milestone 1. Milestone 1 ships RBS for
`Arcp::Envelope` + `Arcp::Serializer`. Each subsequent milestone
ships RBS for the modules it touches. Steep gate runs on the
public-API subset only — internal modules (`Arcp::Runtime::*`) can
remain uncovered, with a `Steepfile` allowlist. Net cost across the
6 milestones: ~30 RBS files. Phase 03 §11 is amended.

### 2.5. Mutation testing — `mutant` on what files?

- `07-tests.md` §1 picks `mutant` nightly on `lib/arcp/envelope.rb`,
  `lib/arcp/session/capability_set.rb`, `lib/arcp/lease/cost_budget.rb`.
- `03-libraries.md` is silent on mutation.

**Resolution:** Phase 07 wins. The three files named are
value-object plumbing where mutants are meaningful. Skip mutation
on `lib/arcp/runtime/*` because timing-dependent mutations survive
under `Async`'s cooperative scheduler. Cost: ~10 CI minutes
nightly, not per-PR.

### 2.6. `Arcp::Errors::Unauthenticated` vs `Arcp::Errors::Unauthorized`

- Spec §12 uses `UNAUTHENTICATED` (not `UNAUTHORIZED`).
- `lib/arcp/error_code.rb:23` already uses `UNAUTHENTICATED`.
- `07-tests.md` §3.4 names a `Arcp::Errors::NotAuthorized` exception
  for the subscribe-no-cancel case.

**Resolution:** Two different concepts, two different classes:
`Arcp::Errors::Unauthenticated` for the `UNAUTHENTICATED` wire code
(no/invalid bearer token, §6.1); `Arcp::Errors::NotAuthorized` (or
better: just raise `Arcp::Errors::PermissionDenied`, the existing
`PERMISSION_DENIED` wire-code class) for the subscribe-can't-cancel
case (§7.6). Phase 07 is amended: use `PermissionDenied`, not a
new `NotAuthorized`. Keeps the error set at exactly 15 classes.

### 2.7. `Arcp::Trace` vs `Arcp::Tracing` rename

- `02-current-audit.md` §4.3 floats renaming `Arcp::Trace` →
  `Arcp::Tracing` "if Phase 04 prefers."
- `04-architecture.md` §1.4 keeps `Arcp::Trace`.

**Resolution:** Keep `Arcp::Trace`. No rename. Fewer renames in the
diff.

---

## 3. Risks

Five risks survive integration, ranked by likelihood × impact.

### 3.1. (H) v1.0 re-baseline is larger than the v1.1 features combined

`02-current-audit.md` §1 enumerates 13 wire-shape divergences;
`02-current-audit.md` §4.2 lists 58 wire-type literals across 14
message files. The audit estimates "half of `lib/arcp/` is renamed
or relocated." Risk: the milestone slips and v1.1 work starts
against a half-migrated base. Mitigation: milestone 1 lands the
envelope + serializer + RBS scaffolding alone (no message-class
renames yet); milestone 2 does the wire-shape rename in one large
but mechanical PR; milestone 3 retires the gRPC-shaped codes in
`lib/arcp/error_code.rb` to the 15-code set and lands the
side-gem extractions. Three landings, each independently testable
against re-baselined `spec/fixtures/envelopes/*.json`.

### 3.2. (H) `Async`-fiber runtime and per-request Puma cannot mix on the runtime side

`02-current-audit.md` §7, `04-architecture.md` §1.3, `05-middleware.md`
§1, `08-docs-readme.md` `guides/deployment.md`. Risk: consumers who
default to a Rails+Puma mental model try to mount
`Arcp::Runtime::Runtime` inside a request handler, observe the
heartbeat timer (`Async::Task#sleep(interval)` registered on welcome
per `04-architecture.md` §3) dying when the request ends, and file
confusion bugs. Mitigation: README quickstart (Phase 08 §4) opens
with deployment model **before** the code snippet;
`arcp-rails`'s engine boot path (Phase 05 §3) hard-checks
`defined?(Falcon::Server)` and refuses to start under Puma without
an explicit `force: true` flag; `arcp-rack` documents the WS
hijack caveat at the top of its README.

### 3.3. (M) The §9.6 budget-decrement race under cooperative Fibers

`04-architecture.md` §3 names the read-modify-write rule;
`07-tests.md` §3.8 tests a 2× concurrent `tool.invoke` scenario.
Risk: the suspension-hygiene rule is documentation, not
enforcement — code review can miss an `await` between budget read
and decrement, and the test only exercises one specific call site.
Mitigation: budget enforcement lives in a single method
(`Arcp::Lease::CostBudget#try_decrement(currency, amount)`) that
does read-check-decrement in straight-line Ruby with **no method
calls that yield to the scheduler** — every call inside is to
stdlib (`BigDecimal#-`, `Hash#[]`, `Hash#[]=`). The method body is
short enough to grep for `await`/`#wait`/`Task#sleep` and gate via
a custom RuboCop cop (deferred — see Phase 07 §4 equivalent;
`07-tests.md` does not write the cop).

### 3.4. (M) Drift between Ruby wire types and TS wire types

`07-tests.md` §2.2 names a `MessageCatalogContractSpec` that asserts
every `MESSAGE_TYPES` value against a checked-in
`spec/fixtures/spec-message-types.json`. Risk: the JSON drifts vs
the TS catalog and the SDKs disagree on the wire. Mitigation: the
JSON is generated from `../spec/docs/draft-arcp-02.1.md` by a
one-time extractor (`bin/extract-spec-messages.rb` — small Ruby
script parsing the §7 + §8 tables); CI runs it and fails on
`git diff --exit-code spec/fixtures/spec-message-types.json` —
same drift-check pattern `09-diagrams.md` uses for `.dot` → `.svg`
regen.

### 3.5. (M) Migration path for current v0.1 consumers

Current `README.md` advertises `v0.1.0` with the RFC-0001 wire
shape and the `Arcp::Client::Client#open / #invoke_tool` API.
Anyone integrated against that surface sees the API change. The
`Arcp::PROTOCOL_VERSION` constant flips from `'1.0'` (the
RFC-0001-misnamed value) to `'1'` (the spec-§5.1 wire literal),
which is itself a confusing transition for users who were grepping
for `1.0`. Mitigation: `MIGRATION-v1.1.md` (Phase 08 §6) lands
with milestone 4 (first v1.1 feature shipping); `CHANGELOG.md`
v1.1 entry (Phase 08 §7) calls this a **breaking change**, not
"additive," because of the v1.0 re-baseline embedded in it. The
`v1.0` Ruby gem version is **not** published as a separate
RubyGems release — `arcp` jumps from `0.1.0` to `1.1.0` in one
move, and consumers track that hop via `MIGRATION-v1.1.md`.

---

## 4. Non-goals

Items explicitly out of scope for the v1.1 milestone. Listing them
so future-me doesn't unwittingly expand the plan.

- **Job pause / unpause** — spec "Not in v1.1" (`01-spec-delta.md`
  §4). No `Feature::JOB_PAUSE` constant; no `Arcp::Job#pause`
  method.
- **Job priority and scheduling hints** — same source.
- **Federation across runtimes** — same source.
- **LLM token streaming surface** — distinct from `result_chunk`
  (final-result streaming, §8.4). Out of v1.1.
- **Renewal of expired leases** — spec §9.5 says renewal is NOT
  supported in v1.1. Cancel and resubmit.
- **Custom RuboCop cop banning suspension inside `CostBudget#try_decrement`** —
  §3.3 above defers it. Phase 07's claim is downgraded to a
  documented review rule.
- **Sub-gem split into `arcp-core` / `arcp-client` / `arcp-runtime`** —
  `04-architecture.md` §1.1 rejected. Single gem.
- **`oj` as default JSON backend** — `03-libraries.md` §1. Stdlib
  `json` default; `oj` opt-in.
- **`standardrb` over `rubocop`** — `03-libraries.md` §13.
- **`rantly` property testing** — `07-tests.md` §1.
- **`mutest` over `mutant`** — `07-tests.md` §1.
- **`Arcp::Core::` namespace prefix** — `04-architecture.md` §1.4.
- **Per-Ruby-version coverage matrix** — `07-tests.md` §6. One
  cell (3.4).
- **Light/dark diagram split** — `09-diagrams.md` §0. Single light
  variant.
- **Sinatra / Roda / Hanami adapter gems** — `05-middleware.md` §5.
  `arcp-rack` covers the control plane for all Rack hosts;
  framework-specific gems would be vanity wrappers.
- **EventMachine-based gems** (`faye-websocket`, `em-websocket`) —
  `05-middleware.md` §5 + `03-libraries.md` §2/§3.
- **`ulid` gem** — `03-libraries.md` §9. `SecureRandom.uuid_v7`
  (Ruby 3.3+ stdlib) handles envelope `id`s; the existing
  hand-rolled `Arcp::Ids::Ulid` value object in `lib/arcp/ids.rb`
  stays as a typed wrapper.

---

## 5. Milestones (PR-sized, ordered)

Each milestone is one PR. Files listed are what changes; spec §
cites identify the contract under test.

### Milestone 1 — Envelope + serializer re-baseline + RBS scaffolding

**Goal:** the envelope speaks v1.0 wire (draft-02 §5) before any
message class is touched; RBS gates the public surface.

| What                                                                                       | Where                                                                                                | Spec §          |
| ------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------- | --------------- |
| Reduce `Arcp::Envelope` from 19 fields to the §5.1 set                                     | `lib/arcp/envelope.rb`                                                                              | §5.1            |
| Flip `Arcp::PROTOCOL_VERSION` from `'1.0'` to `'1'`                                        | `lib/arcp/version.rb`                                                                                | §5.1            |
| Rename `Arcp::Json` → `Arcp::Serializer`; add `backend=` setter for opt-in `oj`            | `lib/arcp/serializer.rb` (rename `lib/arcp/json.rb`)                                                | (Phase 03 §1)   |
| Reject unknown `arcp` values; ignore unknown top-level keys per §5.1                       | `Arcp::Envelope.from_h`                                                                              | §5.1            |
| W3C 32-hex `trace_id` validation                                                           | `lib/arcp/envelope.rb`, `lib/arcp/trace.rb`                                                          | §5.1, §11       |
| Ruby floor: `>= 3.3.0` (`arcp.gemspec`); `TargetRubyVersion: 3.3` (`.rubocop.yml`)         | `arcp.gemspec`, `.rubocop.yml`                                                                       | (§2.2)          |
| Drop `json_schemer` from gemspec                                                            | `arcp.gemspec`                                                                                       | (Phase 03 §7)   |
| Add `bigdecimal ~> 3.1`, `opentelemetry-api ~> 1.5` to gemspec runtime deps                | `arcp.gemspec`                                                                                       | §9.6, §11       |
| Add `async-rspec ~> 1.17`, `rbs ~> 3.6`, `steep ~> 1.9`, `mutant` to dev group              | `Gemfile`                                                                                            | (Phase 07 §1)   |
| Enable `SimpleCov.enable_coverage :branch` + 87% line+branch floor                          | `spec/spec_helper.rb`                                                                                | (Phase 07 §7)   |
| Create `sig/` directory; write RBS for `Arcp::Envelope`, `Arcp::Serializer`, `Arcp::Trace` | `sig/arcp/envelope.rbs`, `sig/arcp/serializer.rbs`, `sig/arcp/trace.rbs`                            | (Phase 03 §11)  |
| Add `Steepfile` with public-surface allowlist                                              | `Steepfile`                                                                                          | (§2.4)          |
| Regenerate envelope fixtures from spec §13                                                  | `spec/fixtures/envelopes/13.*.json`                                                                  | §13             |
| `EnvelopeSpec` updated to assert §5.1 shape                                                | `spec/unit/envelope_spec.rb`                                                                         | §5.1            |

**Gate:** `bundle exec rake` (rspec + rubocop) green; `bundle exec
steep check` green on the new sig files; coverage ≥ 87% on the
touched files. No v1.1 features touched yet.

### Milestone 2 — Message-class rename to v1.0 wire shape

**Goal:** the 58 existing wire-type literals collapse into the v1.0
~16-envelope set.

| What                                                                                                                                                                            | Where                                                                                  | Spec §        |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- | ------------- |
| `session.open/accepted/authenticate/challenge/rejected/refresh/unauthenticated` → `session.hello/welcome/error`                                                                  | `lib/arcp/messages/session.rb` → `lib/arcp/session/*.rb`                              | §6.1, §6.2    |
| `session.close/evicted` → `session.bye`                                                                                                                                          | `lib/arcp/session/bye.rb`                                                              | §6.7          |
| `job.started/completed/failed/cancelled/heartbeat/progress` → `job.submit/accepted/event/result/error`                                                                            | `lib/arcp/messages/execution.rb` → `lib/arcp/job/*.rb`                                | §7.1, §7.3    |
| Unify `log`, `metric`, `event.emit`, `trace.span`, `tool.invoke/result/error/invocations`, `stream.*` into `job.event { kind, body }` with `Arcp::Job::Event::Kind` constants    | `lib/arcp/job/event/*.rb`                                                              | §8.1, §8.2    |
| `cancel/cancel.accepted/cancel.refused` → `job.cancel`                                                                                                                           | `lib/arcp/job/cancel.rb`                                                               | §7.4          |
| `subscribe/subscribe.event/subscribe.accepted/subscribe.closed/unsubscribe` retained as placeholder; v1.1 per-job subscribe lands in milestone 5                                | `lib/arcp/job/subscribe.rb` (stub)                                                     | §7.6          |
| Retire `Arcp::MessageTypeRegistry`; replace with frozen `Arcp::MESSAGE_TYPES` constants                                                                                          | `lib/arcp/message_type.rb`                                                             | (§2.1)        |
| Delete RFC-0001-only files: `lib/arcp/messages/{artifacts,human,permissions,streaming,subscriptions}.rb`; `lib/arcp/runtime/{artifact_store,stream_manager}.rb` (revisit `artifact_ref` as event kind) | (deletes)                                                                              | (Phase 02 §6) |
| RBS for `Arcp::Session::*`, `Arcp::Job::*`, `Arcp::Job::Event::*`                                                                                                                 | `sig/arcp/session/*.rbs`, `sig/arcp/job/*.rbs`                                          | (§2.4)        |
| Regenerate `spec/unit/messages_spec.rb` for renamed classes                                                                                                                      | `spec/unit/messages_spec.rb`                                                           | §6–§8         |
| `MessageCatalogContractSpec` against `spec/fixtures/spec-message-types.json` + `bin/extract-spec-messages.rb`                                                                    | `spec/unit/message_catalog_contract_spec.rb`, `bin/extract-spec-messages.rb`           | §6, §7, §8    |

**Gate:** integration suite (`spec/integration/`) passes against
`MemoryTransport.pair`; WS loopback (`async-websocket`) passes the
handshake → submit → event → cancel scenario; Steep clean.

### Milestone 3 — Error taxonomy + handshake mechanics + sub-gem extractions

**Goal:** the 21 gRPC-named codes in `lib/arcp/error_code.rb`
collapse to 12 v1.0 canonical codes; the
`session.hello`/`welcome`/`bye` handshake works end-to-end;
`arcp-cli` and `arcp-auth-jwt` ship.

| What                                                                                                                                                                                                       | Where                                                                                          | Spec §  |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- | ------- |
| Delete: `OK`, `UNKNOWN`, `INVALID_ARGUMENT` (→ `INVALID_REQUEST`), `DEADLINE_EXCEEDED` (→ `TIMEOUT`), `NOT_FOUND` (→ `JOB_NOT_FOUND`), `ALREADY_EXISTS` (→ `DUPLICATE_KEY`), `RESOURCE_EXHAUSTED`, `FAILED_PRECONDITION`, `ABORTED`, `OUT_OF_RANGE`, `UNIMPLEMENTED`, `UNAVAILABLE`, `DATA_LOSS`, `LEASE_REVOKED`, `BACKPRESSURE_OVERFLOW` | `lib/arcp/error_code.rb`                                                                       | §12     |
| Keep + rename to spec names: `PERMISSION_DENIED`, `LEASE_SUBSET_VIOLATION` (new), `JOB_NOT_FOUND`, `DUPLICATE_KEY`, `AGENT_NOT_AVAILABLE` (new), `CANCELLED`, `TIMEOUT`, `RESUME_WINDOW_EXPIRED` (new), `HEARTBEAT_LOST`, `INVALID_REQUEST`, `UNAUTHENTICATED`, `INTERNAL_ERROR`   | `lib/arcp/error_code.rb`                                                                       | §12     |
| One `Arcp::Errors::*` subclass per code (12 v1.0 in this milestone; 3 v1.1 in milestone 6); each with `CODE` constant + `#code` + frozen `details:`                                                         | `lib/arcp/errors/*.rb`                                                                         | §12     |
| Rewrite `RETRYABLE_BY_DEFAULT` / `NON_RETRYABLE_BY_DEFAULT` sets keyed to the 12-code set                                                                                                                   | `lib/arcp/error_code.rb`                                                                       | §12     |
| `session.hello` / `session.welcome` round-trip integration spec                                                                                                                                            | `spec/integration/handshake_spec.rb`                                                           | §6.2    |
| `session.bye` close spec                                                                                                                                                                                    | `spec/integration/close_spec.rb`                                                               | §6.7    |
| Resume token rotation on every welcome                                                                                                                                                                     | `lib/arcp/runtime/runtime.rb` + spec                                                           | §6.3    |
| Extract `lib/arcp/cli.rb` + `exe/arcp` → `arcp-cli` repo; drop `dry-cli` from core `arcp.gemspec`                                                                                                            | new repo / sub-gem                                                                             | (Phase 04 §1.2) |
| Extract `lib/arcp/auth/jwt.rb` → `arcp-auth-jwt` repo; drop `jwt` from core `arcp.gemspec`                                                                                                                  | new repo / sub-gem                                                                             | (Phase 04 §1.2) |
| Rewrite `CONFORMANCE.md` to the TS shape (~407-line section-by-section matrix), v1.0-only column populated                                                                                                  | `CONFORMANCE.md`                                                                               | §4–§16  |
| `RFC-0001-v2.md`: update pointer or delete and link directly to spec from README                                                                                                                            | `RFC-0001-v2.md`                                                                               | (Phase 08 §8) |

**Gate:** v1.0 conformance harness (`bundle exec rake conformance`)
passes every §4–§12 row. README quickstart updated to v1.0 API
(Phase 08 §4 shape); v0.1 deprecation note added.

**Milestones 1–3 are the v1.0 re-baseline. Below is v1.1 surface.**

### Milestone 4 — Capability negotiation + heartbeat + ack

**Goal:** the foundation v1.1 features that everything else
negotiates against.

| What                                                                                          | Where                                                                                   | Spec §       |
| --------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- | ------------ |
| `Arcp::Session::Feature` constants module (9 entries), `Feature::ALL.freeze`                  | `lib/arcp/session/feature.rb`                                                            | §6.2         |
| `Arcp::Session::CapabilitySet` `Data.define` with `#intersect`, `#supports?`                  | `lib/arcp/session/capability_set.rb`                                                     | §6.2         |
| `Arcp::Session::AgentInventory` + `AgentEntry` with `from_flat` v1.0 compat                   | `lib/arcp/session/agent_inventory.rb`                                                    | §6.2, §7.5   |
| `Hello` / `Welcome` payloads carry `features:` and rich `agents:` shape                       | `lib/arcp/session/hello.rb`, `welcome.rb`                                                | §6.2         |
| `session.ping` / `session.pong` payloads                                                      | `lib/arcp/session/ping.rb`, `pong.rb`                                                    | §6.4         |
| `HeartbeatLoop` via `Async::Task#sleep(interval)`; 2× silence → `Arcp::Errors::HeartbeatLost` | `lib/arcp/session/heartbeat_loop.rb`                                                     | §6.4         |
| `session.ack { last_processed_seq: }`; `Arcp::Runtime::EventLog#evict_up_to(seq)`             | `lib/arcp/session/ack.rb`, `lib/arcp/runtime/event_log.rb` (rename `lib/arcp/store/event_log.rb`) | §6.5      |
| `Arcp::Errors::UnnegotiatedFeature` (library-internal, never on the wire)                     | `lib/arcp/errors/unnegotiated_feature.rb`                                                | (Phase 01 §3.4) |
| `HeartbeatSpec`, `AckSpec`, `CapabilityNegotiationSpec`                                       | `spec/integration/v11/`                                                                  | §6.2–§6.5    |
| Samples: `samples/heartbeat/`, `samples/ack_backpressure/`, `samples/capability_negotiation/` (latter deferred — covered by handshake spec) | `samples/`                                                                               | (Phase 06)   |
| Diagrams: `capability-negotiation.dot`, `heartbeat-flow.dot`, `ack-flow.dot`                  | `docs/diagrams/`                                                                         | (Phase 09)   |
| `docs/concepts/heartbeats.md`, `docs/reference/capabilities.md`                               | `docs/`                                                                                  | §6.2, §6.4   |
| `MIGRATION-v1.1.md` first cut                                                                  | `docs/MIGRATION-v1.1.md`                                                                | (Phase 08 §6) |

**Gate:** Phase 07 §3.1, §3.2, §3.9 specs pass. `bundle exec rake
conformance` adds rows for §6.2, §6.4, §6.5.

### Milestone 5 — List jobs + subscribe + agent versioning

**Goal:** the cross-session observation surface.

| What                                                                                          | Where                                                                                  | Spec §       |
| --------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- | ------------ |
| `session.list_jobs` / `session.jobs` with cursor                                              | `lib/arcp/session/list_jobs.rb`, `jobs_response.rb`                                     | §6.6         |
| Per-principal visibility enforcement in `JobManager#list`                                     | `lib/arcp/runtime/job_manager.rb`                                                       | §6.6         |
| `job.subscribe` / `job.subscribed` / `job.unsubscribe`                                        | `lib/arcp/job/subscribe.rb`, `subscribed.rb`, `unsubscribe.rb`                          | §7.6         |
| `Arcp::Runtime::SubscriptionManager` reworked: principal-scoped, history replay via `from_event_seq` | `lib/arcp/runtime/subscription_manager.rb`                                        | §7.6         |
| Subscriber cannot cancel (client-side block via `Client#subscribe` returning a no-cancel handle + runtime-side `PERMISSION_DENIED` on raw envelope) | `lib/arcp/client/subscribe_handle.rb`, `lib/arcp/runtime/job_manager.rb`         | §7.6         |
| `name@version` parsing via `Arcp::Job::AgentRef.parse`                                        | `lib/arcp/job/agent_ref.rb`                                                              | §7.5         |
| `Arcp::Errors::AgentVersionNotAvailable`                                                      | `lib/arcp/errors/agent_version_not_available.rb`                                         | §12          |
| `ListJobsSpec`, `SubscribeSpec`, `AgentVersionsSpec`                                          | `spec/integration/v11/`                                                                  | §6.6, §7.5, §7.6 |
| Samples: `samples/list_jobs/`, `samples/subscribe/`, `samples/agent_versions/`                | `samples/`                                                                               | (Phase 06)   |
| Diagrams: extended `job-fsm.dot` with subscribe-observer states                               | `docs/diagrams/`                                                                         | (Phase 09)   |
| `docs/concepts/subscribe.md`, `docs/guides/agent-versioning.md`                               | `docs/`                                                                                  | §6.6, §7.5, §7.6 |

**Gate:** Phase 07 §3.3, §3.4, §3.5 pass; cross-principal isolation
asserts exact `job_id` set (no leakage).

### Milestone 6 — Lease expiration + budget + progress + result_chunk + middleware gems + ship

**Goal:** the v1.1 finish line — authority bounds, large-result
streaming, and middleware gems tagged.

| What                                                                                                                                                                             | Where                                                                                  | Spec §       |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- | ------------ |
| `Arcp::Lease::LeaseConstraints` (ISO-8601 UTC `Z` only; `Time#utc?` guard)                                                                                                       | `lib/arcp/lease/lease_constraints.rb`                                                  | §9.5         |
| `Arcp::Runtime::LeaseManager#evaluate` checks `expires_at` via `Process.clock_gettime(Process::CLOCK_MONOTONIC)` on every authority op                                            | `lib/arcp/runtime/lease_manager.rb`                                                    | §9.5         |
| `Arcp::Errors::LeaseExpired` (retryable: false)                                                                                                                                  | `lib/arcp/errors/lease_expired.rb`                                                     | §12          |
| `Arcp::Lease::CostBudget` capability parser (`CCY:amount` grammar) + per-currency counters using `BigDecimal`                                                                    | `lib/arcp/lease/cost_budget.rb`                                                        | §9.6         |
| Decrement on `metric { name: cost.*, unit: <ccy>, value: }`; `try_decrement` straight-line (no `Async` suspension)                                                                | `lib/arcp/runtime/lease_manager.rb`                                                    | §9.6         |
| `Arcp::Errors::BudgetExhausted` (retryable: false)                                                                                                                               | `lib/arcp/errors/budget_exhausted.rb`                                                  | §12          |
| `progress` body — `Arcp::Job::Event::Progress`                                                                                                                                   | `lib/arcp/job/event/progress.rb`                                                       | §8.2.1       |
| `result_chunk` body — `Arcp::Job::Event::ResultChunk`                                                                                                                            | `lib/arcp/job/event/result_chunk.rb`                                                   | §8.4         |
| `JobContext#stream_result` returns an `Async::Queue` whose `each` yields `ResultChunk` bodies; terminating `job.result.result_id` set                                            | `lib/arcp/runtime/job_context.rb`                                                      | §8.4         |
| Reject inline + chunked mix per §8.4                                                                                                                                              | `lib/arcp/runtime/job_manager.rb`                                                      | §8.4         |
| Trace attrs `arcp.lease.expires_at`, `arcp.budget.remaining`                                                                                                                     | `lib/arcp/trace.rb`                                                                    | §11          |
| `LeaseExpiresAtSpec`, `CostBudgetSpec`, `ResultChunkSpec`, `ProgressSpec`                                                                                                        | `spec/integration/v11/`                                                                | §8.4, §9.5, §9.6 |
| Samples: `samples/lease_expires_at/`, `samples/cost_budget/`, `samples/progress/`, `samples/result_chunk/`                                                                       | `samples/`                                                                             | (Phase 06)   |
| Diagrams: `result-chunk-sequence.dot`, `progress-events.dot`; final `job-fsm.dot` form                                                                                            | `docs/diagrams/`                                                                       | (Phase 09)   |
| Side gems tagged 1.1.0: `arcp-rack`, `arcp-falcon`, `arcp-rails`, `arcp-otel`                                                                                                     | (separate repos)                                                                       | (Phase 05)   |
| `docs/concepts/leases.md`, `docs/guides/{budgets,result-streaming}.md`                                                                                                            | `docs/`                                                                                | §8.4, §9.5, §9.6 |
| `CHANGELOG.md` v1.1 entry; `MIGRATION-v1.1.md` final                                                                                                                              | `CHANGELOG.md`, `docs/MIGRATION-v1.1.md`                                              | (Phase 08)   |
| Mutation testing (`mutant`) nightly job: MSI ≥ 95% on `lib/arcp/envelope.rb`, `lib/arcp/session/capability_set.rb`, `lib/arcp/lease/cost_budget.rb`                              | `.github/workflows/nightly-mutation.yml`                                              | (Phase 07 §1) |
| Tag `arcp` 1.1.0; publish to RubyGems                                                                                                                                            | git tag + `gem push`                                                                   | —            |

**Gate:** `bundle exec rake conformance` reports every §4–§12 row
passing for v1.0 + v1.1. README + `MIGRATION-v1.1.md` ship. All 18
samples runnable via `ruby samples/<name>/run.rb` exiting 0.

---

## 6. Cross-cutting deliverables

These touch every milestone, not one specific one:

- **CI matrix** (Phase 07 §6): Ruby 3.3 base, Ruby 3.4 with coverage
  + 87% line+branch gate. Bundler `--prefer-lowest` cell on 3.3.
- **RuboCop** (Phase 02 §3, Phase 03 §13): `TargetRubyVersion: 3.3`
  (flipped from 3.4 in milestone 1) with `rubocop-performance`,
  `rubocop-rake`, `rubocop-rspec` plugins. No regression.
- **Steep / RBS** (`02-current-audit.md` §3, Phase 03 §11): added in
  milestone 1; allowlist grows per milestone.
- **`Rakefile` tasks** (Phase 02 §3): keep `default` running `rspec
  + rubocop`. Add `conformance` (milestone 3 onward), `docs`
  (milestone 6), `diagrams` (milestone 4 onward) invoking
  `bin/render-diagrams.sh`.
- **`CONFORMANCE.md`** rewritten in milestone 3 (v1.0 column) and
  extended per-milestone (4: §6.2, §6.4, §6.5; 5: §6.6, §7.5, §7.6;
  6: §8.4, §9.5, §9.6, §11, §12 new codes).
- **Lefthook** (`02-current-audit.md` §3): existing `pre-commit:
  rubocop` and `pre-push: rake` continue. No new hooks unless
  Steep needs one (Phase 07 §1).
- **Anti-slop hygiene** (every Phase brief): banned filler in PR
  descriptions, README, docs. Code blocks in docs/samples run
  as-is — `bundle exec rake docs:test` (Phase 08) extracts and
  runs them.

---

## 7. Open questions

Items not resolved by the nine phase files; each needs a decision
**before** the milestone that depends on it lands.

1. **Single repo or many for the side gems?** Phase 04 §1.2 says
   each side gem (`arcp-cli`, `arcp-auth-jwt`) gets its own repo,
   and Phase 05 follows the same shape for the four host adapters.
   The workspace memory notes `ruby-sdk/` is one repo (workspace
   layout: `/Users/nficano/code/arpc/`). Decide: separate
   `arcp-cli` / `arcp-rack` / etc. repos, or a `bundler-subgems`
   pattern shipping all from one repo with multiple gemspecs.
   Default: **separate repos** unless the workspace owner overrides.

2. **`arcp-rails` mode — sidecar Falcon engine or ActionCable
   tunnel?** `05-middleware.md` §3 documents both modes honestly.
   The ActionCable-tunnel mode reuses Rails auth at the cost of
   double envelope decoding. Decide which is the default `bin/rails
   arcp:install` generates. Default: **sidecar Falcon engine**
   (ships first; tunneling lands as an opt-in flag in a v1.2
   milestone).

3. **OTEL extension key for in-envelope trace propagation —
   `x-vendor.opentelemetry.tracecontext` or a different reserved
   name?** `05-middleware.md` §4 reads the TS source as treating it
   as a vendor extension. Spec §15 governs extension namespace
   conventions; verify before milestone 6 wiring.

4. **YARD vs RDoc.** `03-libraries.md` §12 (docs) implicitly keeps
   YARD (`yard ~> 0.9` is in the current `Gemfile`). `08-docs-readme.md`
   §3 wires `.yardopts`. RDoc would also work and is stdlib-bundled.
   Decide if YARD's `@example`/`@yieldparam` tags justify keeping
   the extra dep. Default: **keep YARD** — the `@example` tags
   matter for the runnable-code-blocks rule.

5. **Sub-gem branch / tag strategy.** The core gem jumps from
   `0.1.0` to `1.1.0` in milestone 6. Side gems (`arcp-cli`,
   `arcp-auth-jwt`) start at `1.1.0` to match. Middleware gems
   (`arcp-rack`, etc.) also tag `1.1.0` in milestone 6. Confirm
   versioning lockstep before publishing.

Resolve via the workspace owner (`nficano@gmail.com`) before
milestone 1 lands. Open questions 1, 2, 3 are technical decisions;
4 is a tooling pick; 5 is a release-process question.

---

## 8. Reading order for an incoming contributor

If a new contributor lands here cold:

1. `BOOTSTRAP.md` (in this dir) — the brief.
2. `01-spec-delta.md` — what v1.1 adds.
3. `02-current-audit.md` — what the SDK is now (and why §1 is
   bigger than it looks).
4. `04-architecture.md` — the target shape.
5. **This file** — milestone order.
6. The phase file for whichever milestone they're picking up
   (Phase 03 for gems, 05 for adapters, 06 for samples, 07 for
   tests, 08 for docs, 09 for diagrams).

`02-current-audit.md` §6 (the v1.0 re-baseline list) is the single
most load-bearing section in the plan — read it twice.
