# ARCP Ruby SDK Samples

Numbered short samples (`01_*`–`06_*`) live alongside fourteen
single-purpose sample directories, each named for the protocol
primitive it demonstrates.

> **Illustrative, not runnable.** Each example imports `arcp` as if
> it were a published gem. Setup boilerplate (transport URL,
> identity, auth) is elided as `client = nil # ARCPClient(...)`. LLM
> and framework calls live in tiny stub modules so the protocol code
> in `main.rb` is what you read.

## The fourteen primitives

| Directory | Demonstrates | Spec |
|---|---|---|
| [`subscriptions/`](./subscriptions) | Three Observer clients on one session, three filters, three sinks. | §5, §13 |
| [`leases/`](./leases) | Lease-gated shell agent. Reads coarse, writes scoped. | §15.4–§15.5 |
| [`lease_revocation/`](./lease_revocation) | Per-table leases with `lease.revoked` / `lease.extended` mid-flight. | §15.5 |
| [`permission_challenge/`](./permission_challenge) | Two-party permission challenge — generator asks, reviewer holds veto. | §15.4, §6.4 |
| [`delegation/`](./delegation) | `agent.delegate` fan-out + `JobMux` to demux events by `job_id`. | §14, §6.4 |
| [`handoff/`](./handoff) | `agent.handoff` with transcript packed as artifact, runtime fingerprint pinned. | §14, §16, §8.3 |
| [`heartbeats/`](./heartbeats) | Worker federation; heartbeat-loss reroute via `idempotency_key`. | §10.3, §6.4 |
| [`capability_negotiation/`](./capability_negotiation) | Capability-driven peer routing; standard `cost.usd` rollups. | §7, §17.3.1, §18.3 |
| [`resumability/`](./resumability) | Real crash and resume via `Process.exit!` + `resume` envelope. | §10, §19, §6.4 |
| [`reasoning_streams/`](./reasoning_streams) | `kind: thought` stream + a peer runtime that subscribes and delegates critiques back. | §11.4, §13, §14 |
| [`extensions/`](./extensions) | Custom `arcpx.sdr.*.v1` namespace with correct unknown-message handling. | §21 |
| [`human_input/`](./human_input) | `human.input.request` fanned across phone/email/Slack; first-wins resolution. | §12 |
| [`cancellation/`](./cancellation) | Cooperative `cancel` (terminate) vs `interrupt` (pause and ask). | §10.4–§10.5 |
| [`mcp/`](./mcp) | ARCP runtime fronting an MCP server: `tool.invoke` → MCP `call_tool`. | §20 |

## Conventions

- Ruby 3.4+, `# frozen_string_literal: true` on every file, single
  quotes per repo `.rubocop.yml`.
- Each example is one `main.rb` (the protocol code) + 0–2 stub
  modules named for what they elide (`agents.rb`, `steps.rb`,
  `cheap.rb`, `synth.rb`, `work.rb`, `channels.rb`, `sql.rb`,
  `upstream.rb`, `sinks/*.rb`).
- `client = nil # ARCPClient(...)` literally — transport, identity,
  and auth are setup noise, not the point.
- Envelopes match RFC-0001 v2 exactly. Custom message types follow
  §21.1 `arcpx.<domain>.<name>.v<n>` naming.
- `Async {}` blocks for concurrency, `case/in` pattern matching for
  envelope dispatch, `Data.define` for value objects.

## What's where in the SDK

- `Arcp::Client::Client` — handshake driver.
- `Arcp::Envelope.build(type:, payload:, ...)` — envelope minting.
- `Arcp::Envelope`, `Arcp::ErrorCode`, `Arcp::Error` — wire primitives.
- `Arcp::Transport::WebSocket` / `Arcp::Transport::Memory` — transports.
- `Arcp::Store::EventLog` — SQLite schema reused by `subscriptions`.

## Reading order

For a brisk tour: `subscriptions`, `leases`, `delegation`,
`resumability` (this one actually crashes and recovers),
`cancellation`, `extensions`, `mcp`. These seven exercise the bulk
of the protocol.
