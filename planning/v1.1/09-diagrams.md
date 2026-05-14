# 09 — Diagrams

Eight Graphviz sources under `docs/diagrams/*.dot`, rendered to
sibling `.svg`s and committed in lockstep. The set covers module
dependency, the two FSMs (session, job), and four protocol sequences
(capability negotiation, heartbeat, ack, result chunk + progress).
Every diagram cites the spec § it visualizes in its `label=` caption;
Phase 08 `docs-readme.md` references them by relative path.

The TypeScript SDK ships paired light/dark variants
(`../typescript-sdk/diagrams/diagram-template-{light,dark}.dot`,
`<picture>` element with `prefers-color-scheme`). The Ruby SDK
deliberately ships a **single light variant per diagram**. Rationale:
the diagrams live under `docs/diagrams/` next to YARD output
(Phase 08), not in a marketing README; a single canvas keeps the
repository smaller and avoids the structural-drift CI burden the TS
README warns about ("Light and dark variants must be structurally
identical — same nodes, same edges, same cluster boundaries"). If a
later milestone wants dark, the script in §10 below copies the light
`.dot`, swaps the palette block, and emits a paired SVG.

## 1. Shared style block

Each `.dot` file opens with the same canvas / node / edge defaults,
copy-pasted (no `.dotinclude` mechanism exists). One place to change
the palette: a `bin/render-diagrams.sh` lint step greps for the
canonical defaults header before invoking `dot`, failing the build if
a diagram drifted (cited under §10).

```dot
// Canvas
bgcolor="white";
fontname="Helvetica";
fontsize=10;
compound=true;

// Node defaults
node [
  shape=box,
  style="rounded,filled",
  fillcolor="#f8f9fa",
  color="#cbd5e1",
  fontname="Helvetica",
  fontsize=10
];

// Edge defaults
edge [
  fontname="Helvetica",
  fontsize=9,
  color="#475569"
];
```

FSM terminal-state overrides (applied per-node, never globally):

- error terminals: `shape=doublecircle, fillcolor="#fee2e2", color="#fca5a5"`
- success terminals: `shape=doublecircle, fillcolor="#dcfce7", color="#86efac"`

Sequence diagrams use vertical lanes built from one `subgraph
cluster_<peer>` per participant, each with
`style="rounded,filled", fillcolor="#f8f9fa", color="#cbd5e1"`, and
edges drawn between numbered step-nodes inside the lanes. `mscgen`
would render a true sequence diagram, but adds a non-Graphviz
toolchain dependency for one feature; `rankdir=TB` with ordered ranks
inside each lane (`{rank=same; client_2; runtime_2;}`) reproduces the
visual without that cost. The pattern matches the same-rank trick
documented in `../typescript-sdk/diagrams/README.md` lines 233–242.

No color outside the palette:
`#f8f9fa` (node fill), `#cbd5e1` (border), `#475569` (edge text + ink),
`#fee2e2` / `#fca5a5` (error), `#dcfce7` / `#86efac` (success), white
canvas. No blue/amber anchor convention — that's a TS template choice
(`../typescript-sdk/diagrams/README.md` lines 100–119) and would
duplicate semantics the FSM-state coloring already carries here.

## 2. Per-diagram specifications

Each row: filename, purpose, render command, node/edge inventory,
spec § cited in the caption. Captions live in a graph-level
`label="..."` with `labelloc=b`.

### 2.a `module-deps.dot`

**Purpose:** Hand-maintained module / gem dependency graph for the
`arcp` core gem and its satellites from Phase 04 §1.2–§1.3, so the
namespace boundaries from `04-architecture.md` §1.4 are checkable by
eye.

**Render:** `dot -Tsvg docs/diagrams/module-deps.dot -o docs/diagrams/module-deps.svg`

**Nodes (rounded boxes, default fill):**

- **Core module cluster** (`cluster_core`, label "arcp gem"):
  `Arcp::Envelope`, `Arcp::Session`, `Arcp::Job`, `Arcp::Lease`,
  `Arcp::Errors`, `Arcp::Transport`, `Arcp::Auth`, `Arcp::Trace`,
  `Arcp::Client`, `Arcp::Runtime`. These ten match the flat namespace
  listed in `04-architecture.md` §1.4.
- **Satellite gem nodes** (outside `cluster_core`): `arcp-cli`,
  `arcp-auth-jwt`, `arcp-otel`, `arcp-rack`, `arcp-falcon`,
  `arcp-rails`. Names from `04-architecture.md` §1.2 + §1.3.

**Edges** (directed, "A → B" reads "A depends on B"):

- `Arcp::Client → Arcp::Session`, `Arcp::Client → Arcp::Transport`,
  `Arcp::Client → Arcp::Envelope`, `Arcp::Client → Arcp::Job`,
  `Arcp::Client → Arcp::Errors`.
- `Arcp::Runtime → Arcp::Session`, `Arcp::Runtime → Arcp::Transport`,
  `Arcp::Runtime → Arcp::Envelope`, `Arcp::Runtime → Arcp::Job`,
  `Arcp::Runtime → Arcp::Lease`, `Arcp::Runtime → Arcp::Errors`.
- `Arcp::Session → Arcp::Envelope`, `Arcp::Session → Arcp::Auth`,
  `Arcp::Session → Arcp::Trace`.
- `Arcp::Job → Arcp::Envelope`, `Arcp::Job → Arcp::Lease`,
  `Arcp::Job → Arcp::Errors`.
- `Arcp::Lease → Arcp::Errors` (for `LEASE_EXPIRED` / `BUDGET_EXHAUSTED`
  per `01-spec-delta.md` §2).
- `Arcp::Transport → Arcp::Envelope`, `Arcp::Transport → Arcp::Errors`.
- Satellites (each depends on at least one core module):
  - `arcp-cli → Arcp::Client`, `arcp-cli → Arcp::Runtime`,
    `arcp-cli → Arcp::Errors` (extracted from `lib/arcp/cli.rb` +
    `exe/arcp`, `04-architecture.md` §1.2).
  - `arcp-auth-jwt → Arcp::Auth` (extracted from `lib/arcp/auth/jwt.rb`).
  - `arcp-otel → Arcp::Trace`, `arcp-otel → Arcp::Session`
    (parity with `@arcp/middleware-otel`).
  - `arcp-rack → Arcp::Transport`, `arcp-rack → Arcp::Runtime`.
  - `arcp-falcon → Arcp::Transport`, `arcp-falcon → Arcp::Runtime`
    (the canonical host per `03-libraries.md` §3).
  - `arcp-rails → Arcp::Transport`, `arcp-rails → Arcp::Runtime`
    (ActionCable bridge).

**Caption:** `"arcp v1.1 module/gem dependency graph — Phase 04 §1.1–§1.4 (hand-maintained)"`.

**Hand-maintenance note in the file header comment:** Ruby has no
direct equivalent of `deptrac` (PHP) or `dependency-cruiser` (JS) for
gem-internal module boundaries. `packwerk` is the closest Ruby tool
but is Rails-coupled — it expects `app/`, `config/application.rb`,
and ActiveSupport's autoloader — and is out of scope for a non-Rails
SDK gem per the bootstrap hard rule ("No `Rails`-coupled deps in the
core gem"). Drift detection is therefore a code-review concern: the
diagram is rebuilt when `lib/arcp/` adds a `require` that crosses a
module boundary not yet on the graph. Phase 07 may add an RSpec
matcher that walks every `lib/arcp/**/*.rb`'s `require_relative`
calls and asserts the edge exists here; until then, eyeballs.

### 2.b `session-fsm.dot`

**Purpose:** Session lifecycle on the client side, including the v1.1
heartbeat-loss close path from spec §6.4.

**Render:** `dot -Tsvg docs/diagrams/session-fsm.dot -o docs/diagrams/session-fsm.svg`

**States (nodes):**

- `init` — `Arcp::Client.connect` called, no transport yet.
- `hello_sent` — `session.hello` written to transport per `01-spec-delta.md` §3.4 step 2.
- `welcome_received` — `session.welcome` decoded, `effective` capability set frozen on the `Session` value (`01-spec-delta.md` §3.4 step 4).
- `live` — at least one envelope flowed in each direction since last interval (spec §6.4).
- `pinging` — `heartbeat_interval_sec` elapsed with no inbound message; `session.ping` emitted, awaiting `session.pong`.
- `error` — terminal error state (red double-circle). Reached from
  `hello_sent` on a `session.error` welcome rejection, or from
  `pinging` when no `session.pong` arrives within the second interval
  (`HEARTBEAT_LOST`).
- `closed` — terminal success-style double-circle. Reached on a
  client-initiated `session.close` from `live` or `pinging`.

**Edges (with labels):**

- `init → hello_sent` `[label="send session.hello (§6.2)"]`
- `hello_sent → welcome_received` `[label="recv session.welcome (§6.2)"]`
- `hello_sent → error` `[label="recv session.error / transport reset"]`
- `welcome_received → live` `[label="ack capabilities intersection"]`
- `live → pinging` `[label="interval idle (§6.4)"]`
- `pinging → live` `[label="recv session.pong"]`
- `pinging → live` `[label="recv any envelope"]` (any inbound message resets the idle timer per §6.4 paragraph 1)
- `pinging → error` `[label="2× interval silence → HEARTBEAT_LOST (§6.4)"]`
- `live → closed` `[label="send session.close (§6.7)"]`
- `pinging → closed` `[label="send session.close (§6.7)"]`

**Caption:** `"Arcp::Session client-side FSM — spec §6.2, §6.4, §6.7"`.

### 2.c `job-fsm.dot`

**Purpose:** Job FSM with v1.1 additions: subscribe attaches an
observer that does not change the submitter's state; lease expiration
and budget exhaustion drop the running state into terminal error.
Spec §7.1, §7.3, §7.6, §9.5, §9.6.

**Render:** `dot -Tsvg docs/diagrams/job-fsm.dot -o docs/diagrams/job-fsm.svg`

**States (nodes):**

- `submit_sent` — client emitted `job.submit` (§7.1).
- `accepted` — runtime returned `job.accepted` with `job_id` and effective lease (§7.1).
- `running` — `job.event[*]` streaming.
- `running_with_subscriber` — same as `running`, plus at least one
  `Arcp::Runtime::SubscriptionManager` attachment (Phase 04 §1.4
  names the manager). Drawn as a parallel state, not a successor: an
  arrow from `running` reads `attach subscriber (§7.6)` and an arrow
  back reads `unsubscribe (§7.6)`. The state of the submitter is
  unchanged; this is purely an observer fan-out.
- `success` — terminal success double-circle. Reached via `job.result`
  with `final_status: "success"` (§8.4 terminator when streaming, or
  inline result).
- `error{cancelled}` — terminal error (`CANCELLED`, §12).
- `error{timed_out}` — terminal error (`TIMEOUT`, §12).
- `error{lease_expired}` — terminal error (`LEASE_EXPIRED`, §9.5 +
  §12). v1.1 addition.
- `error{budget_exhausted}` — terminal error (`BUDGET_EXHAUSTED`,
  §9.6 + §12). v1.1 addition.

The four `error{*}` nodes share `shape=doublecircle, fillcolor="#fee2e2"`;
`success` uses `fillcolor="#dcfce7"`. v1.1 terminals carry a
`(v1.1)` suffix in the label to make the delta visible at a glance.

**Edges:**

- `submit_sent → accepted` `[label="recv job.accepted (§7.1)"]`
- `submit_sent → error{cancelled}` `[label="recv job.error CANCELLED before accept"]`
- `accepted → running` `[label="first job.event"]`
- `running → success` `[label="recv job.result success (§8.4 terminator)"]`
- `running → error{cancelled}` `[label="send job.cancel → job.error CANCELLED (§7.4)"]`
- `running → error{timed_out}` `[label="max_runtime_sec elapsed → job.error TIMEOUT (§7.1, §12)"]`
- `running → error{lease_expired}` `[label="lease.expires_at reached → job.error LEASE_EXPIRED (§9.5)"]`
- `running → error{budget_exhausted}` `[label="cost.budget ≤ 0 → job.error BUDGET_EXHAUSTED (§9.6)"]`
- `running → running_with_subscriber` `[label="job.subscribe (§7.6)"]`
- `running_with_subscriber → running` `[label="job.unsubscribe (§7.6)"]`
- `running_with_subscriber → success` `[label="job.result — fan-out to all subscribers"]`
- (the four error transitions out of `running_with_subscriber` are
  drawn but labeled identically to the `running →` ones; visually
  they're the same fan-out — terminal state is shared.)

**Caption:** `"Arcp::Job FSM with v1.1 subscribe, lease, budget — spec §7.1, §7.3, §7.6, §9.5, §9.6, §12"`.

### 2.d `capability-negotiation.dot`

**Purpose:** Sequence of the hello/welcome handshake from spec §6.2
plus `01-spec-delta.md` §3.4. Shows that effective set = intersection,
stored immutably on both sides.

**Render:** `dot -Tsvg docs/diagrams/capability-negotiation.dot -o docs/diagrams/capability-negotiation.svg`

**Lanes (two `subgraph cluster_*`, top-to-bottom step ranking):**

- `cluster_client` (label "Arcp::Client") — five step nodes
  `client_1..client_5`.
- `cluster_runtime` (label "Arcp::Runtime") — four step nodes
  `runtime_1..runtime_4`.

**Step contents:**

- `client_1`: "Build `CapabilitySet.new(features: Feature::ALL, encodings: …, agents: nil)`" (`01-spec-delta.md` §3.1 + §3.2).
- `client_2`: "Emit `session.hello { capabilities: { features, encodings } }`".
- `runtime_1`: "Decode `session.hello`; build runtime `CapabilitySet`".
- `runtime_2`: "`effective = remote.intersect(local)` (`01-spec-delta.md` §3.2)".
- `runtime_3`: "Emit `session.welcome { capabilities: { features, encodings, agents: AgentInventory } }` (`01-spec-delta.md` §3.3)".
- `client_3`: "Decode `session.welcome`; build runtime `CapabilitySet`".
- `client_4`: "`effective = local.intersect(remote)` — same result as runtime by definition".
- `client_5`: "Freeze `Session#capabilities = effective`; subsequent feature-gated sends check `session.capabilities.supports?(Feature::HEARTBEAT)` etc.".
- `runtime_4`: "Freeze runtime `Session#capabilities = effective`".

**Edges (cross-lane, dashed for ack-style returns, solid for sends):**

- `client_2 → runtime_1` `[label="session.hello"]`
- `runtime_3 → client_3` `[label="session.welcome"]`

Within each lane: invisible `style=invis` edges between consecutive
step nodes plus `{rank=same; client_n; runtime_m;}` constraints to
enforce vertical ordering and horizontal alignment of correlated
steps. The pattern is the same as
`../typescript-sdk/diagrams/README.md` §"Same-rank trick".

**Caption:** `"Capability negotiation — spec §6.2, §7.5; client+runtime intersection (01-spec-delta.md §3.4)"`.

### 2.e `heartbeat-flow.dot`

**Purpose:** Two consecutive idle intervals plus the failure path from
spec §6.4 and §13.1.

**Render:** `dot -Tsvg docs/diagrams/heartbeat-flow.dot -o docs/diagrams/heartbeat-flow.svg`

**Lanes:** `cluster_client` (label "client peer"), `cluster_runtime`
(label "runtime peer"). Either side may initiate per §6.4 — the
diagram uses the spec §13.1 mix: client pings first, then runtime
pings.

**Step nodes (one per envelope or timer event, top-to-bottom):**

- `t0`: "interval clock starts (heartbeat_interval_sec from welcome)".
- `client_1`: "30s idle elapses → emit `session.ping { nonce: p1, sent_at }`".
- `runtime_1`: "recv `session.ping`; emit `session.pong { ping_nonce: p1, received_at }`".
- `client_2`: "recv `session.pong`; reset idle timer".
- `runtime_2`: "30s idle elapses → emit `session.ping { nonce: p2, sent_at }`".
- `client_3`: "recv `session.ping`; emit `session.pong { ping_nonce: p2 }`".
- `runtime_3`: "recv `session.pong`; reset idle timer".

Then a parallel failure branch (drawn off to the right with a
horizontal divider node `divider` styled `shape=plaintext`):

- `runtime_4`: "alt: 2× interval silence after `session.ping p2`".
- `runtime_5`: "close transport; surface `HEARTBEAT_LOST` (§6.4, §12)" — error double-circle.
- `runtime_6`: "**MUST NOT** terminate jobs (§6.4 paragraph 3); session lives through resume window".

Heartbeats are deliberately **not** numbered with `event_seq` —
§6.4 final paragraph. Note this in a small annotation node
`shape=note, fillcolor="#f8f9fa"` linked to `client_1` by a dashed
`constraint=false` edge labeled "not in event_seq".

**Edges:**

- `client_1 → runtime_1` `[label="session.ping (§6.4)"]`
- `runtime_1 → client_2` `[label="session.pong"]`
- `runtime_2 → client_3` `[label="session.ping"]`
- `client_3 → runtime_3` `[label="session.pong"]`
- `runtime_4 → runtime_5` `[label="close (§6.4 paragraph 2)"]`
- `runtime_5 → runtime_6` `[style=dashed, label="jobs continue (§6.4 paragraph 3)"]`

**Caption:** `"Heartbeat liveness — spec §6.4 + example §13.1"`.

### 2.f `ack-flow.dot`

**Purpose:** §6.5 acknowledgement and early eviction. The diagram
visualizes the buffer trim from §13.2.

**Render:** `dot -Tsvg docs/diagrams/ack-flow.dot -o docs/diagrams/ack-flow.svg`

**Lanes:** `cluster_runtime` (label "Arcp::Runtime + EventLog
buffer"), `cluster_client` (label "Arcp::Client consumer"). The
runtime lane includes a `cluster_buffer` inner cluster holding five
cylinder-shaped event nodes `e1..e5` (cylinder per
`../typescript-sdk/diagrams/README.md` line 94 "Data stores use
shape=cylinder").

**Step nodes:**

- `runtime_1`: "emit `job.event[seq=1..5]`" — five solid arrows from `runtime_1` to `e1..e5` (annotate "EventLog appends").
- `e1..e5`: each labeled `event_seq=N` inside `cluster_buffer`.
- `client_1`: "receive `e1..e3`; process; lag at e4..e5".
- `client_2`: "emit `session.ack { last_processed_seq: 3 }`".
- `runtime_2`: "recv `session.ack`; MAY evict `e1..e3` (§6.5 bullet 1)".
- `e1..e3`: re-style with dashed border + lighter fill after ack to
  signal "trimmed early" — done as a second copy of the cluster
  beneath the first, since Graphviz can't restyle a node mid-graph.
- `runtime_3`: "MUST NOT evict `e4..e5` (§6.5 bullet 2); resume window still applies".

**Edges:**

- `client_2 → runtime_2` `[label="session.ack { last_processed_seq: 3 } (§6.5)"]`
- `e1 → trash` `[style=dashed, color="#475569", label="evict (§6.5)"]` (same for `e2`, `e3`); `trash` is a single sink node `shape=note, label="freed (early)"`.

A second annotation node clarifies the advisory nature: "ack is
advisory; resume still requires `last_event_seq` (§6.5 final
paragraph)" — dashed `constraint=false` edge from `client_2`.

**Caption:** `"Event acknowledgement — spec §6.5 + example §13.2"`.

### 2.g `result-chunk-sequence.dot`

**Purpose:** `result_chunk` streaming from agent through runtime to
client, terminated by `job.result { result_id, result_size }` per
§8.4 and §13.6. Shows that inline result and chunks are mutually
exclusive (§8.4 final paragraph).

**Render:** `dot -Tsvg docs/diagrams/result-chunk-sequence.dot -o docs/diagrams/result-chunk-sequence.svg`

**Lanes:** `cluster_agent` (label "agent process"), `cluster_runtime`
(label "Arcp::Runtime"), `cluster_client` (label "Arcp::Client
result_chunk consumer — `Enumerator::Lazy[String]` per
`04-architecture.md` §3.3").

**Step nodes (top-to-bottom):**

- `agent_1`: "begin streaming; runtime allocates `result_id = res_01J…` (§8.4 paragraph 4 bullet 1)".
- `agent_2..agent_N`: "emit `job.event { kind: result_chunk, body: { result_id, chunk_seq: k, data, encoding: utf8|base64, more: true } }` for `k ∈ 0..N-2`".
- `agent_final`: "emit final chunk `chunk_seq: N-1, more: false`".
- `agent_terminator`: "emit `job.result { final_status: success, result_id, result_size }` (§8.4 paragraph 5)".
- `runtime_1..runtime_N`: pass-through; runtime preserves `chunk_seq` order (§8.4 bullet 2 "MUST be emitted in order").
- `client_1..client_N`: decode each chunk by `encoding`; `Enumerator::Lazy` yields each `data` after decode.
- `client_assemble`: "on `more: false`, await `job.result`; assert `result_size == sum(decoded_chunk.bytesize)`".
- `client_done`: success double-circle "final result is concatenation in `chunk_seq` order (§8.4 paragraph 5)".

For brevity the diagram shows `N=3`: chunks 0, 1, 2 with 2 being
`more: false`, then `job.result`.

**Edges:**

- `agent_k → runtime_k` `[label="result_chunk seq=k"]` for k ∈ 0..2.
- `runtime_k → client_k` same label.
- `agent_terminator → runtime_term → client_assemble` `[label="job.result { result_id, result_size } (§8.4)"]`.
- Plus a dashed `constraint=false` annotation edge from `agent_2` to
  a `shape=note` node "MUST NOT mix inline `payload.result` with
  `result_chunk` (§8.4 paragraph 6)".

**Caption:** `"Result streaming — spec §8.4 + example §13.6"`.

### 2.h `progress-events.dot`

**Purpose:** Visualize `kind: progress` interleaved with other event
kinds to make clear it is one `event_seq` slot among many (§8.2.1,
§8.3 unchanged ordering).

**Render:** `dot -Tsvg docs/diagrams/progress-events.dot -o docs/diagrams/progress-events.svg`

**Lanes:** `cluster_runtime`, `cluster_client`. No `cluster_agent`
this time — the diagram is about how the client *renders* progress,
not about where the agent emits it. (The agent's role is implicit in
`runtime_k`.)

**Step nodes (chronological event stream from runtime):**

- `runtime_1`: "`job.event[seq=12] { kind: log, body: { level: info, message: 'starting' } }`".
- `runtime_2`: "`job.event[seq=13] { kind: progress, body: { current: 12, total: 120, units: 'files' } } (§8.2.1)`".
- `runtime_3`: "`job.event[seq=14] { kind: tool_call, body: { tool: 'fs.read', args: …, call_id: … } }`".
- `runtime_4`: "`job.event[seq=15] { kind: progress, body: { current: 47, total: 120 } } (§8.2.1)`".
- `runtime_5`: "`job.event[seq=16] { kind: progress, body: { current: 120, total: 120, message: 'done indexing' } }`".
- `runtime_6`: "`job.event[seq=17] { kind: status, body: { phase: finalizing } }`".
- `client_1`: "decode all → frozen `Arcp::Job::Event` `Data` values (`04-architecture.md` §2.3)".
- `client_2`: "pattern match on `kind`: progress arms update a progress gauge; others route to their respective handlers (`case ev in { kind: 'progress', body: { current:, total: } }`)".

**Edges:**

- Six `runtime_k → client_k_decoded` arrows, two of which are
  highlighted (thicker `penwidth=1.4`) — the two `progress` events
  at seq=13, seq=15, seq=16. The non-`progress` events get a normal
  edge to underscore that the protocol takes no action on progress
  (§8.2.1 paragraph 4 "advisory only").
- A note node `shape=note, label="progress is advisory; protocol
  takes no action (§8.2.1)"` attached to the highlighted edges by a
  dashed `constraint=false` edge.

**Caption:** `"Progress events interleaved — spec §8.2.1, §8.3"`.

## 3. Build pipeline

`Rakefile` adds one task; the renderer is a shell script so CI can
invoke it without booting a Ruby environment.

`Rakefile`:

```ruby
desc "Render all docs/diagrams/*.dot to .svg"
task :diagrams do
  sh "bin/render-diagrams.sh"
end
```

`bin/render-diagrams.sh` (committed, `chmod +x`, shebang `#!/usr/bin/env bash`,
`set -euo pipefail`):

- Verifies `dot -V` reports `graphviz version 12.` (pinned major).
- Greps each `docs/diagrams/*.dot` for the canonical defaults header
  block from §1 above; fails the script if any diagram has drifted —
  cheaper than maintaining an actual `.dotinclude` since GraphViz
  doesn't support includes.
- For each `f.dot`, runs `dot -Tsvg "$f" -o "${f%.dot}.svg"`.

SVGs are committed alongside `.dot` so `bundle exec yard` (Phase 08)
and the GitHub source view both render without a Graphviz install.
The TS SDK's `../typescript-sdk/diagrams/` follows the same
commit-the-rendered-artifact convention.

CI step (Phase 07 owns the matrix; this is the diagram-specific
check):

```yaml
- name: Render diagrams
  run: bundle exec rake diagrams
- name: Detect diagram drift
  run: git diff --exit-code docs/diagrams/
```

Drift means a `.dot` was edited without re-rendering; `git diff
--exit-code` flips the build to red. Pinning Graphviz to a single
major version on the CI image (e.g. `apt-get install -y
graphviz=2.42.*` on Ubuntu 22.04, or the equivalent
`graphviz=12.x` pin on a newer base) keeps SVG output byte-stable —
Graphviz 9 → 10 reshuffled `<g>` ordering in SVG output and would
otherwise produce spurious diffs. Phase 07 declares the CI image and
pin alongside the Ruby version matrix.

## 4. Where these diagrams land in the docs

Phase 08 `docs-readme.md` references each SVG by relative path from
`docs/`:

| Diagram                          | Embedded in                                |
| -------------------------------- | ------------------------------------------ |
| `module-deps.svg`                | `docs/architecture/overview.md`            |
| `session-fsm.svg`                | `docs/sessions/lifecycle.md`               |
| `job-fsm.svg`                    | `docs/jobs/lifecycle.md`                   |
| `capability-negotiation.svg`     | `docs/sessions/handshake.md`               |
| `heartbeat-flow.svg`             | `docs/sessions/heartbeat.md`               |
| `ack-flow.svg`                   | `docs/sessions/acknowledgement.md`         |
| `result-chunk-sequence.svg`      | `docs/jobs/result-streaming.md`            |
| `progress-events.svg`            | `docs/jobs/progress.md`                    |

YARD's `--asset docs/diagrams` flag in `.yardopts` (Phase 08) copies
the SVGs into the generated API site so a class-doc reader sees the
same image without leaving YARD.
