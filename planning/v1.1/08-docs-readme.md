# 08 — Docs & README

Sources of truth: `../spec/docs/draft-arcp-02.1.md` (spec), the TS
docs at `../typescript-sdk/docs/`, `./README.md` (current, keyed to
RFC-0001), `./CONFORMANCE.md` (5-line stub today, per
`02-current-audit.md` §1), `planning/v1.1/01-spec-delta.md`,
`planning/v1.1/02-current-audit.md`, `planning/v1.1/04-architecture.md`,
`planning/v1.1/06-examples.md`.

Phase 04 and Phase 06 are not yet authored at the time of writing;
their constraints (module map per `02-current-audit.md` §4.3,
sample-tree shape per BOOTSTRAP Phase 06) are taken from the
bootstrap brief. This plan binds to those interfaces and will not
shift if Phase 04/06 fill in their detail consistent with the
bootstrap.

The Ruby docs site reads the same shared frontmatter as TS; the
`arcp.dev` static-site builder ingests `docs/**/*.md` keyed by
frontmatter and renders YARD output from `docs/api/`.

This plan does not author prose — it specifies the file tree,
frontmatter, YARD configuration, README outline, voice rules,
migration note, CHANGELOG entry, and the pointer-file fix.

## 1. `docs/` tree

Mirror the TS shape (`../typescript-sdk/docs/`: `getting-started.md`,
`architecture.md`, `transports.md`, `cli.md`, `recipes.md`,
`troubleshooting.md`, `guides/*`, `packages/*`), with three Ruby-
specific departures called out below.

```
docs/
  getting-started.md              kind: guide,     order: 0
  architecture.md                 kind: reference, order: 1
  transports.md                   kind: reference, order: 2
  cli.md                          kind: guide,     order: 3   (pointer-only — see §1.4)
  recipes.md                      kind: guide,     order: 80
  troubleshooting.md              kind: guide,     order: 90

  concepts/                       kind: concept    (wire-level "what")
    sessions.md                   spec_sections: [§6.1, §6.2]
    jobs.md                       spec_sections: [§7]
    leases.md                     spec_sections: [§9]
    events.md                     spec_sections: [§8]
    heartbeats.md                 spec_sections: [§6.4]
    subscribe.md                  spec_sections: [§7.6]
    delegation.md                 spec_sections: [§10, §9.4]
    resume.md                     spec_sections: [§6.3]
    auth.md                       spec_sections: [§6.1]
    vendor-extensions.md          spec_sections: [§5.1, §8.2, §15]

  guides/                         kind: guide      (API-level "how")
    quickstart.md                 spec_sections: [§6, §7]
    agent-versioning.md           spec_sections: [§7.5, §12]
    budgets.md                    spec_sections: [§9.6, §12]
    result-streaming.md           spec_sections: [§8.4]
    deployment.md                 spec_sections: []    (Ruby-only — see §1.3)
    observability.md              spec_sections: [§11]
    rack-host.md                  spec_sections: [§4.1]
    falcon-host.md                spec_sections: [§4.1]
    rails.md                      spec_sections: [§4.1]

  reference/                      kind: reference
    errors.md                     spec_sections: [§12]
    capabilities.md               spec_sections: [§6.2]   (Ruby-only — see §1.2)
    conformance.md                spec_sections: [all]    (mirrors top-level CONFORMANCE.md)
    extensions-config.md          spec_sections: [§15]

  api/                            (YARD output — generated, .gitignored)
  diagrams/                       (Phase 09 owns; referenced from concept pages)

  MIGRATION-v1.1.md               (see §6)
```

### 1.1. Why split TS `guides/` into Ruby `concepts/` + `guides/`

TS bundles "what is a session on the wire" and "how do I open one in
TS" into one file per spec section. Ruby has more API surface to
document per concept (`Async`-based connect/`Sync { }` wrappers,
`Enumerator::Lazy` over `Async::Queue` for streams, RBS sigs) and
the wire-level "what" is identical across the spec ecosystem.
Splitting lets `concepts/sessions.md` cross-link from
`../typescript-sdk/docs/guides/sessions.md` and from any future
language SDK, while `guides/quickstart.md` and other Ruby-specific
"how" pages stay short.

### 1.2. `reference/capabilities.md` (Ruby-only)

Documents the closed `Arcp::Session::Feature` constants from
`01-spec-delta.md` §3.1: `HEARTBEAT`, `ACK`, `LIST_JOBS`,
`SUBSCRIBE`, `LEASE_EXPIRES_AT`, `COST_BUDGET`, `PROGRESS`,
`RESULT_CHUNK`, `AGENT_VERSIONS`. Notes that `Feature::ALL.freeze`
is closed by convention (v1.2 features land in a new version, not by
silently growing the constant). TS doesn't need an equivalent page —
its feature names live inline as string literals in the runtime API.

### 1.3. `guides/deployment.md` (Ruby-only)

Documents the daemon-not-per-request-worker constraint from
`02-current-audit.md` §7: an ARCP runtime is one of (a) a daemon
under `systemd`/Docker/Kamal, (b) a Falcon-hosted process via
`arcp-falcon`, or (c) an ActionCable bridge inside an existing
Rails process via `arcp-rails`. **Not** a classic Puma-per-request
worker — heartbeat timers (`Async::Task` on a `welcome` interval per
`01-spec-delta.md` §1 row §6.4), event buffers, and `job.subscribe`
listeners do not survive a per-request worker. TS doesn't need this
page — Node servers and Bun are both single-process by default.

### 1.4. `cli.md` is a pointer-only page in core docs

The `arcp` CLI moves to a separate `arcp-cli` sub-gem per
`02-current-audit.md` §6 item 9 and §2 (`dry-cli` dep moves with
it). `docs/cli.md` in core is a 10-line stub pointing at the
sub-gem's own README; the current README's CLI paragraph
(`./README.md:27–36`) moves there.

### 1.5. `guides/{rack-host,falcon-host,rails}.md` — one per host adapter

These mirror the host-adapter gems from Phase 05 (`arcp-rack`,
`arcp-falcon`, `arcp-rails` per the bootstrap brief). Each page
shows: gem add, mount snippet, host-header / DNS-rebind defense,
where WS upgrade happens (`Rack::Hijack` vs
`Async::WebSocket::Adapters::Rack`). Phase 05 owns the underlying
adapter design; Phase 08 owns the doc page outlines only.

### 1.6. Dropped vs TS

- `docs/packages/bun.md` — no Ruby analogue.
- `docs/packages/hono.md` — no Ruby analogue.
- `docs/packages/node.md` — no Ruby analogue (Rack covers the
  "generic host" slot).
- `docs/packages/express.md`, `docs/packages/fastify.md` — folded
  into Ruby `guides/rack-host.md` and `guides/falcon-host.md`.

### 1.7. Concept page outline (uniform shape)

Each `docs/concepts/*.md` is the same five-section page:

1. **What** — one paragraph, spec § link as the first sentence.
2. **Wire shape** — fenced JSON of the envelope.
3. **In Ruby** — three-to-six-line `Arcp::*` snippet that runs
   under the `rake docs:test` extractor (see §5).
4. **State / lifecycle** — short list of transitions; concept pages
   that have an FSM link the Phase 09 diagram.
5. **See also** — `guides/<name>.md` for the "how", spec § anchor.

### 1.8. Guide page outline

Each `docs/guides/*.md`:

1. **Goal** — one sentence.
2. **Prerequisites** — gems installed, Ruby floor.
3. **Steps** — numbered list, each step a runnable snippet.
4. **Verify** — one-line check (`ruby samples/<name>/run.rb` exits
   0; the relevant `Async::Queue#each` yielded N events; etc.).
5. **Troubleshooting** — three-to-five anti-FAQ bullets, each
   linking `docs/troubleshooting.md#<anchor>`.

## 2. Frontmatter convention

Every authored `docs/*.md` opens with YAML frontmatter. The shared
docs site at `arcp.dev` reads it; GitHub renders the YAML block as
plain text and the body as markdown.

```yaml
---
title: Sessions
sdk: ruby
spec_sections: [§6.4, §6.5]
order: 10
kind: concept
---
```

| Field           | Type                | Required | Notes                                                                                       |
| --------------- | ------------------- | -------- | ------------------------------------------------------------------------------------------- |
| `title`         | string              | yes      | One-word or short phrase. Renders as `<h1>` substitute; do not duplicate as a `#` heading.  |
| `sdk`           | `ruby`              | yes      | Static. Allows the docs site to namespace by SDK.                                           |
| `spec_sections` | array of `§X.Y`     | yes      | Empty array `[]` is allowed for Ruby-only pages (deployment, capabilities reference).       |
| `order`         | integer             | yes      | Stable ordinal within `kind`. Convention: top-level 0–10, concepts 10–30, guides 30–80.     |
| `kind`          | `concept`/`guide`/`reference` | yes | Exactly one of these. Drives left-nav grouping on `arcp.dev`.                            |

`kind` per file:

| Path                          | `kind`     |
| ----------------------------- | ---------- |
| `docs/getting-started.md`     | guide      |
| `docs/architecture.md`        | reference  |
| `docs/transports.md`          | reference  |
| `docs/cli.md`                 | guide      |
| `docs/recipes.md`             | guide      |
| `docs/troubleshooting.md`     | guide      |
| `docs/concepts/*.md`          | concept    |
| `docs/guides/*.md`            | guide      |
| `docs/reference/*.md`         | reference  |
| `docs/MIGRATION-v1.1.md`      | reference  |

Lint: a `bundle exec rake docs:lint` task (Phase 07 wires the rake
hook) parses each frontmatter block with `YAML.safe_load`, asserts
the required keys, asserts `kind ∈ {concept, guide, reference}`,
asserts `spec_sections` entries match `/\A§\d+(\.\d+)*\z/`, and
asserts `order` is unique within `(kind, directory)`. Fail-on-warn.

## 3. YARD configuration

`02-current-audit.md` §3 records: `yard ~> 0.9` is declared in the
gemspec but no `.yardopts` exists. Phase 08 adds it.

### 3.1. `.yardopts` (new file at repo root)

```
--output-dir docs/api
--protected
--no-private
--exclude lib/arcp/cli.rb
--markup markdown
--markup-provider redcarpet
--readme README.md
--files CHANGELOG.md,docs/MIGRATION-v1.1.md
-
lib/**/*.rb
```

Notes:

- `--exclude lib/arcp/cli.rb` — the CLI moves to `arcp-cli`
  (`02-current-audit.md` §6 item 9). Until the move lands the file
  exists in-tree; once it's gone the exclude line is removed.
- `--no-private` keeps internal helpers (`Arcp::Runtime::PendingRegistry`
  per current tree) out of the public surface. Phase 04 owns which
  classes are public; YARD honors the `@api private` tag too.
- `--markup-provider redcarpet` — Phase 03 picks the gem; if Kramdown
  is preferred, swap the provider line. The choice is not in this
  phase.

### 3.2. Required YARD tags on every public method

Public surface = anything in `Arcp::Client`, `Arcp::Runtime`,
`Arcp::Session`, `Arcp::Job`, `Arcp::Transport::*`, `Arcp::Errors::*`
(per `02-current-audit.md` §4.3). Each public method documents:

| Tag           | Required? | Notes                                                                                                                                |
| ------------- | --------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `@param`      | yes for each non-block param | Include type. Use `String`, `Integer`, `Symbol`, `Arcp::*`, `Async::Task` — not `Object`.                       |
| `@return`     | yes       | Use `void` for command methods; `Async::Task<T>` for the I/O-returning entrypoints (per Phase 04 concurrency model).                |
| `@raise`      | yes when the method raises a typed error | Use the 15 `Arcp::Errors::*` subclasses (per `01-spec-delta.md` §2 and `02-current-audit.md` §6 item 6).      |
| `@example`    | yes for class-level surface (`Client#submit`, `Runtime#register_agent`, `Session#list_jobs`) | Block must run under the `rake docs:test` extractor.            |
| `@since 1.1.0`| yes for every new v1.1 method | Lets readers and `arcp.dev` filter "what's new in 1.1".                                                              |
| `@yieldparam` | yes when the method yields | Used for `subscribe { |env| … }` (Phase 04 concurrency seam from `01-spec-delta.md` §1 row §7.6).                          |
| `@api`        | yes for `@api private` | Mark internal helpers explicitly; YARD's default visibility is not enough.                                                       |

Concrete examples of `@raise` directives (one per spec error code,
mapped from `01-spec-delta.md` §2 and `02-current-audit.md` §6 item
6):

```
@raise [Arcp::Errors::BudgetExhausted]          §9.6 — per-currency budget hit zero
@raise [Arcp::Errors::LeaseExpired]             §9.5 — operation past expires_at
@raise [Arcp::Errors::AgentVersionNotAvailable] §7.5 — name@version not registered
@raise [Arcp::Errors::ResumeWindowExpired]      §6.3 — past resume_window_sec
@raise [Arcp::Errors::HeartbeatLost]            §6.4 — two missed pongs
@raise [Arcp::Errors::PermissionDenied]         §12  — cross-session subscribe
@raise [Arcp::Errors::InvalidRequest]           §12  — malformed payload before send
```

The exhaustive list is the 15-code set per `02-current-audit.md` §6
item 6; Phase 04 finalises the class names.

### 3.3. `bundle exec rake docs`

Add a Rake task in `Rakefile`:

- `rake docs` — runs `yard doc`, writes to `docs/api/`.
- `rake docs:lint` — frontmatter lint (§2).
- `rake docs:test` — extracts every fenced ` ```ruby ` block from
  `docs/**/*.md`, runs each as a one-off `ruby -e` (Phase 07 may
  generalise; see §5). Exits non-zero on any failure.
- `rake docs:server` — local `yard server`; useful for editor preview.

The default `rake` task (`rspec` + `rubocop` per
`02-current-audit.md` §3 Lefthook row) does **not** run `docs:test`
to keep developer-loop fast; CI runs `docs:test` explicitly.

### 3.4. Ship YARD output in-repo? No.

`.gitignore` adds `docs/api/`. YARD output is regenerated in CI for
the docs site (the `arcp.dev` site builder runs `bundle exec rake
docs` and ingests `docs/api/`). Shipping the generated HTML in the
gem itself bloats the published gem; `arcp.gemspec`'s `spec.files`
glob already excludes `docs/api/` once it's gitignored.

## 4. README outline

Heading list + one sentence per section. No prose. The current
README (`./README.md`) is keyed to RFC-0001 and v1.0 status — full
rewrite. Total target: ~150 lines, scannable in 2 minutes.

```
# arcp — Ruby SDK for the Agent Runtime Control Protocol v1.1
  One-paragraph header: what this gem is (Ruby reference implementation
  of ARCP v1.1, additive over v1.0), link to spec.

## Install
  `gem 'arcp'` for Gemfiles and `bundle add arcp` for one-shot adds;
  Ruby floor (see §4.1 below).

### Ruby version compatibility
  Two-column table (Ruby version × support level): 3.3 supported,
  3.4 supported. Notes: `bigdecimal` must be in the consumer Gemfile
  (Ruby 3.4 unbundled, per `02-current-audit.md` §2 "Not declared"
  row); `logger` declared in `arcp.gemspec` since Ruby 3.4 unbundled it.

## Quickstart
  A 30-line `ruby` snippet (single file, no `bundle exec`, no
  `pairMemoryTransports`-style ceremony) showing register-agent +
  submit-and-stream via an in-process `Arcp::Transport::Memory` pair;
  the canonical runnable is `samples/quickstart/run.rb` per
  `01-spec-delta.md` §3.4 and BOOTSTRAP Phase 06.

## What is ARCP
  One paragraph: sessions, jobs, immutable per-job leases, one event
  stream, resume token. Link to `../spec/docs/draft-arcp-02.1.md`.
  No marketing words (see §5).

## What this SDK does NOT do
  One-line bullets:
  - No auth-server. Consumers bring a bearer issuer; `arcp-auth-jwt`
    is the optional verifier sub-gem.
  - No job scheduling. Deferred to ARCP v1.2 per
    `01-spec-delta.md` §4.
  - No LLM token streaming as a first-class shape. v1.1 has
    `result_chunk` (§8.4) for final-result streaming only.
  - No Puma-only runtime hosting. Falcon required for WS per
    `02-current-audit.md` §7; see `docs/guides/deployment.md`.

## Packaging
  Table:
  | Gem               | One-line purpose                                                              |
  | ----------------- | ----------------------------------------------------------------------------- |
  | `arcp`            | Core: envelope, session, job, lease, transport, runtime, client.              |
  | `arcp-cli`        | `arcp` executable (was in core; moves out per audit §6.9).                    |
  | `arcp-auth-jwt`   | JWT bearer verifier (was in core; moves out per audit §6.11).                 |
  | `arcp-rack`       | Rack mount + WS upgrade attachment for any Rack-compatible host.              |
  | `arcp-falcon`     | Falcon-native mount via `Async::WebSocket::Adapters::Rack`.                   |
  | `arcp-rails`      | ActionCable bridge for embedding inside a Rails app.                          |
  | `arcp-otel`       | OpenTelemetry span + W3C trace context propagation (§11).                     |

  Cross-reference Phase 05 for adapter design; this README states
  only the gem names and one-line purposes.

## Deployment model
  Two sentences: the runtime is a long-lived process. Hosted by a
  daemon (systemd/Docker/Kamal), Falcon (`arcp-falcon`), or
  ActionCable (`arcp-rails`); not Puma-per-request. Pointer to
  `docs/guides/deployment.md` and `02-current-audit.md` §7.

## CLI
  Two sentences: pointer to `arcp-cli` sub-gem README; the current
  README's inline CLI paragraph (`./README.md:27–36`) moves there.

## Conformance
  Pointer to `CONFORMANCE.md` (full TS-shape matrix, rewritten per
  `02-current-audit.md` §1 — the 5-line stub goes away).

## Documentation
  Pointer to `docs/`, with the same two-column guide table as
  `../typescript-sdk/README.md:29–36` but keyed to Ruby
  `docs/concepts/` + `docs/guides/`.

## Development
  Four-line block: `bundle install`, `bundle exec rake`,
  `bundle exec rake docs`, `bundle exec rake docs:test`.

## License
  Apache-2.0 (unchanged from current README line 135).
```

### 4.1. Ruby floor

`BOOTSTRAP.md` states 3.3+ as the floor; `arcp.gemspec`
(`02-current-audit.md` §2) pins `>= 3.4.0`. **Phase 03 owns the
decision** (per `02-current-audit.md` §9 Phase 03 row: "defend
keeping 3.4 or relax to 3.3"). README writes whatever Phase 03
decides; if not yet decided when README lands, state both: "Ruby
3.3 minimum (gemspec pins 3.4 — see Phase 03 decision in
`planning/v1.1/03-libraries.md`)".

### 4.2. Quickstart correctness

Current README quickstart (`./README.md:21–25`) reads
`bundle exec ruby samples/01_minimal_session.rb`. Per
`02-current-audit.md` §6 item 5 the v1.0 re-baseline rewrites the
samples tree; BOOTSTRAP Phase 06 names samples by feature
(`samples/quickstart/`, `samples/result_chunk/`, …) not by index.
The new quickstart points at `samples/quickstart/run.rb`. Phase 06
freezes the final path.

### 4.3. README-as-runnable rule

Every fenced ` ```ruby ` block in the README must run as written
under `rake docs:test`. No pseudocode, no `# ...` ellipses
substituting for real code. State this as a rule in the README's
"Development" section so contributors know.

## 5. Voice

Terse. No marketing copy. No emojis. Every code block runs.

Banned words (per BOOTSTRAP anti-slop guardrails and reiterated
here): "leverage", "robust", "scalable", "performant", "powerful",
"modern", "elegant", "magic", "Rails-like" (as filler).

Banned constructs:

- Adjectives without a referent ("highly configurable" — by what
  measure, against what baseline?).
- "Just" as in "just call X" (assumes the reader already knows).
- "We" or "the team" — third-person impersonal; the SDK is the
  subject.
- Pseudocode (`// ...` or `# do the thing here`) — fails
  `rake docs:test`.

Rule: every paragraph cites one of {spec §, TS path, current-SDK
path, named gem, Ruby idiom}. Same rule the planning docs follow.

`rake docs:test` enforces runnability: extracts every fenced
` ```ruby ` block (matching `/```ruby\n.*?\n```/m`) from `README.md`,
`CHANGELOG.md`, and `docs/**/*.md`, writes each to a tmpfile, and
runs `ruby -W0 <tmpfile>` with a 10s timeout. Exit code zero or
explicit `# docs:test: skip` marker → pass; anything else → fail.
Phase 07 may move the extractor to its own gem if the pattern
recurs.

## 6. `MIGRATION-v1.1.md`

New file at `docs/MIGRATION-v1.1.md`. One page. Frontmatter `kind:
reference`, `order: 0` (top of `reference/` group), `title: Migrating
to v1.1`, `spec_sections: [§6.2, §12]`.

Audience: existing v0.1 / RFC-0001 consumers (the only published
revision today, per `02-current-audit.md` §1). The headline is that
v0.1 → v1.1 is not "add v1.1 features" — it is "wire-shape rebase
to v1.0 first, then v1.1 additions" (per `02-current-audit.md` §6).

Sections, in order:

1. **Why** — one paragraph. The v0.1 implementation tracked
   RFC-0001 (`../spec/docs/draft-arcp-01.md`); the published spec
   is now v1.1 (`../spec/docs/draft-arcp-02.1.md`). The wire shapes
   differ.

2. **Wire-shape rebase** — bulleted list, one bullet per item in
   `02-current-audit.md` §6 (numbered 1–11 there):
   - Envelope shrinks from 19 fields to 8 (`02-current-audit.md`
     §6 item 1).
   - `arcp` literal flips from `"1.0"` to `"1"` (item 2).
   - Handshake renames: `session.open` → `session.hello`,
     `session.accepted` → `session.welcome`, `session.rejected` →
     `session.error`; auth folds into `hello.payload.auth` (item 3).
   - Job lifecycle: `job.submit` → `job.accepted` replaces
     `job.started` (item 4).
   - Events unify under `job.event { kind:, body: }` — `log`,
     `metric`, `event.emit`, `trace.span`, `tool.invoke`,
     `tool.result`, `tool.error`, `stream.chunk` collapse (item 5).
   - `session.close` / `session.evicted` → `session.bye` (item 7).

3. **Module renames** — bulleted list mirroring
   `02-current-audit.md` §4.3 deltas:
   - `Arcp::Json` → `Arcp::Serializer`.
   - `Arcp::Client::Client` → `Arcp::Client`.
   - `Arcp::Auth::JwtAuth` → moves to `arcp-auth-jwt` gem.
   - `Arcp::CLI` + `exe/arcp` → move to `arcp-cli` gem.
   - `Arcp::Messages::*` reshapes per the 14-modules → 16-envelopes
     map (audit §4.2 vs §4.3).

4. **Error-code retirements** — bulleted list of removed constants
   from `lib/arcp/error_code.rb` (audit §6 item 6): `OK`, `UNKNOWN`,
   `INVALID_ARGUMENT`, `DEADLINE_EXCEEDED`, `NOT_FOUND`,
   `ALREADY_EXISTS`, `RESOURCE_EXHAUSTED`, `FAILED_PRECONDITION`,
   `ABORTED`, `OUT_OF_RANGE`, `UNIMPLEMENTED`, `UNAVAILABLE`,
   `DATA_LOSS`, `LEASE_REVOKED`, `BACKPRESSURE_OVERFLOW`. Plus
   three additions (`01-spec-delta.md` §2):
   `AGENT_VERSION_NOT_AVAILABLE`, `LEASE_EXPIRED` (re-wired),
   `BUDGET_EXHAUSTED`.

5. **Removed dependencies** — `json_schemer` (audit §6 item 10),
   `jwt` moves to `arcp-auth-jwt` (item 11), `dry-cli` moves to
   `arcp-cli` (item 9).

6. **Sample tree** — old `samples/0N_*.rb` index names → new
   feature-named `samples/<feature>/run.rb` (BOOTSTRAP Phase 06).

7. **No code migration aids ship** — there is no `arcp-v01-shim`
   gem; the gap is large enough that a shim would be larger than
   the rewrite. Stated explicitly so consumers don't wait for one.

No marketing. No "before/after we" framing.

## 7. CHANGELOG

`CHANGELOG.md` is presumably a stub (not read in the bootstrap
file list; treat as a stub for planning purposes). Append a v1.1
entry following Keep-a-Changelog headings. Outline:

```
## [1.1.0] — TBD

### Added
- ARCP v1.1 wire support: session.ping/pong (§6.4),
  session.ack (§6.5), session.list_jobs (§6.6), job.subscribe (§7.6),
  agent versioning (§7.5), result_chunk events (§8.4),
  progress events (§8.2.1), lease_constraints.expires_at (§9.5),
  cost.budget capability (§9.6).
- Capability negotiation: `Arcp::Session::Feature`,
  `Arcp::Session::CapabilitySet`, `Arcp::Session::AgentInventory`
  (per `planning/v1.1/01-spec-delta.md` §3).
- Three new error classes: `Arcp::Errors::AgentVersionNotAvailable`,
  `Arcp::Errors::LeaseExpired`, `Arcp::Errors::BudgetExhausted`.
- Host adapter gems: `arcp-rack`, `arcp-falcon`, `arcp-rails`,
  `arcp-otel`.
- `.yardopts`; `rake docs`, `rake docs:lint`, `rake docs:test`.

### Changed
- Wire shape rebased to ARCP v1.0 (`../spec/docs/draft-arcp-02.md`)
  as the floor for v1.1 additions. See `docs/MIGRATION-v1.1.md`.
- Envelope reduced from 19 fields to 8 per §5.1.
- `PROTOCOL_VERSION` flips from `"1.0"` to `"1"`.
- Error-code taxonomy: 21 gRPC-style codes → 15 spec codes (12 v1.0
  + 3 v1.1). See migration note.
- `Arcp::Client::Client` → `Arcp::Client`; `Arcp::Json` →
  `Arcp::Serializer`.

### Removed
- `Arcp::Auth::JwtAuth` (moved to `arcp-auth-jwt`).
- `Arcp::CLI`, `exe/arcp` (moved to `arcp-cli`).
- `json_schemer` runtime dependency.
- Top-level wire types collapsed into `job.event`: `log`, `metric`,
  `event.emit`, `trace.span`, `tool.{invoke,result,error}`,
  `stream.{chunk,close,error,open}`.

### Migration
- See `docs/MIGRATION-v1.1.md` and `CONFORMANCE.md`.
```

Date stamp is set at release; planning leaves "TBD".

## 8. `RFC-0001-v2.md` pointer fix

`./README.md:4` links to `RFC-0001-v2.md`, which per
`02-current-audit.md` §9 currently points at
`../spec/docs/draft-arcp-01.md`. Two options:

| Option                                        | Pros                                                                                                                                                                       | Cons                                                                                       |
| --------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| Update `RFC-0001-v2.md` pointer               | Preserves anchor URLs people may have linked to.                                                                                                                            | Keeps a file whose content is a one-line pointer.                                          |
| Delete `RFC-0001-v2.md`; rename to `SPEC.md`  | One fewer file; README links directly to `../spec/docs/draft-arcp-02.1.md`.                                                                                                 | Breaks any external links to `RFC-0001-v2.md`.                                             |
| Delete `RFC-0001-v2.md`; no replacement       | Cleanest. README has a single direct spec link, same as `../typescript-sdk/README.md:7`.                                                                                    | Same breakage as rename.                                                                   |

**Recommendation: delete `RFC-0001-v2.md` outright.** The TS README
links directly to `../spec/docs/draft-arcp-02.md` with no
intermediate pointer file (TS README line 7); Ruby mirrors that. The
file's purpose was to host the RFC-0001 draft inline in v0.1; that
content is obsolete now and the spec lives in `../spec/docs/`. The
v1.1 README links straight to `../spec/docs/draft-arcp-02.1.md`.

This decision is implementation-cheap; Phase 10 synthesis can
override if there's an external-link consideration this plan
doesn't see.

## 9. Hand-off

| Owner                | Item                                                                                                                                                |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| Phase 04             | Finalise the `Arcp::Errors::*` class names so `@raise` directives in §3.2 are exact.                                                                |
| Phase 05             | Final API for `arcp-rack`, `arcp-falcon`, `arcp-rails` so `docs/guides/{rack-host,falcon-host,rails}.md` outlines map to real method signatures.    |
| Phase 06             | Final sample-tree paths so `README.md` quickstart and `docs/getting-started.md` point at real files.                                                |
| Phase 07             | `rake docs:test` extractor (one option: build it; alternative: extend an existing tester gem). Whichever, it is the CI gate this plan depends on.   |
| Phase 09             | Diagrams under `docs/diagrams/` that concept pages reference (§1.7 step 4 of the page outline).                                                     |
| Phase 10             | Override the `RFC-0001-v2.md` delete recommendation (§8) if external-link cost is non-trivial.                                                      |
