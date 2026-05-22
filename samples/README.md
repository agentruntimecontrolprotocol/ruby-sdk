# Samples

Each subdirectory is a self-contained runnable example with three files:

| File | Purpose |
| --- | --- |
| `server.rb` | Sets up `Arcp::Runtime::Runtime`, registers the agent, and starts a transport. |
| `client.rb` | Connects, submits a job, observes events, and prints the result. |
| `run.rb` | Wires the two together with `MemoryTransport.pair` and runs them under `Sync { }`. |

## Running an example

```
bundle exec ruby samples/<name>/run.rb
```

All examples depend only on the gems in the repo `Gemfile`.

## Samples

| Directory | What it demonstrates | Spec |
| --- | --- | --- |
| `ack_backpressure` | `session.ack` and backpressure signalling | §6.5, §14 |
| `agent_versions` | `name@version` pinning and `AGENT_VERSION_NOT_AVAILABLE` | §7.5 |
| `cancel` | Client-initiated cancellation mid-flight | §7 |
| `cost_budget` | `cost.budget` capability with `try_spend!` and `BudgetExhausted` | §9.6 |
| `custom_auth` | Custom `AuthScheme` implementation replacing `Bearer` | §6.1 |
| `delegate` | Handler emitting a `delegate` event with a subset lease | §10 |
| `heartbeat` | `heartbeat_interval_sec` ping/pong keepalive | §6.4 |
| `idempotent_retry` | `idempotency_key` reuse returning the same `job_id` | §13 |
| `lease_expires_at` | Lease with `expires_at` and `LeaseExpired` on overshoot | §9.3, §9.5 |
| `lease_violation` | `LeaseSubsetViolation` raised from `Subsetting.bound` | §9.4 |
| `list_jobs` | Paginated `list_jobs` with cursor walking | §6.6 |
| `progress` | Periodic `progress` events consumed via subscribe | §8.3 |
| `provisioned_credentials` | `InMemoryProvisioner` issuing + revoking scoped keys | §9.7–§9.8 |
| `result_chunk` | `stream_result` producer and chunk-assembling consumer | §8.4 |
| `resume` | Transport drop, reconnect with `resume_token` + `last_event_seq` | §6.3 |
| `stdio` | Runtime and client connected over `StdioTransport` (child process) | §5 |
| `submit_and_stream` | Minimal submit → subscribe → get_result end-to-end | §7 |
| `subscribe` | Cross-session observation (`client_b` watching `client_a`'s job) | §7.6 |
| `vendor_extensions` | Emitting and receiving `x-vendor.*` event kinds | §15 |

## TypeScript-only examples not ported

The TypeScript SDK ships additional examples that target Node.js-specific HTTP
server integrations. These are intentionally not ported — Ruby uses different
server libraries with their own adapter patterns.

| TS example | Why not ported | Ruby equivalent |
| --- | --- | --- |
| `bun` | Bun is a JavaScript runtime | Use `falcon` or any Rack-compatible server — see [`docs/deployment.md`](../docs/guides/deployment.md) |
| `express` | Express is a Node.js framework | Use Sinatra: `gem 'sinatra'` + `Async::WebSocket::Adapters::Rack` |
| `fastify` | Fastify is a Node.js framework | Use Rack middleware or Roda with the `websockets` plugin |
| `hono` | Hono targets JS runtimes (Bun, Deno, CF Workers) | No direct equivalent; use Rack or Falcon directly |

For WebSocket server integration in Ruby see [`docs/guides/deployment.md`](../docs/guides/deployment.md).
For stdio-based child-process agents see the [`stdio`](stdio/) sample.
