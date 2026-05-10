# arcp — Ruby SDK for the Agent Runtime Control Protocol

Reference Ruby implementation of the **Agent Runtime Control Protocol**
([ARCP](RFC-0001-v2.md)) v1.0.

## Status

`v0.1.0` — protocol fundamentals are in. See
[CONFORMANCE.md](CONFORMANCE.md) for what is implemented and what is
deferred. The implementation prioritises correctness and readability
over speed; idiomatic Ruby (Data.define, case/in, the async gem,
fiber-local trace context) is used throughout.

## Requirements

- Ruby 3.4+ (uses pattern matching, `Data.define`, fiber-local storage)
- Bundler 2.x

## Quickstart

```sh
bundle install
bundle exec rake          # rspec + rubocop
bundle exec ruby samples/01_minimal_session.rb
```

The `arcp` CLI is also installed by the gem (`bundle exec arcp`):

```
arcp version
arcp serve --transport stdio        # blocks on stdin/stdout
arcp serve --transport ws --bind 127.0.0.1:7777
arcp tail   path/to/event-log.sqlite
arcp replay path/to/event-log.sqlite --after msg_xyz
arcp send   ping '{}'
```

## Architecture

```
+-------------------------+        +---------------------------+
|  Arcp::Client::Client   |  <-->  |  Arcp::Runtime::Runtime   |
|  - open / invoke / ping |        |  - SessionNegotiator      |
|  - cancel / interrupt   |        |  - JobManager             |
|  - on_human_input       |        |  - StreamManager          |
|  - on_permission        |        |  - LeaseManager           |
+-------------------------+        |  - SubscriptionManager    |
            ^                      |  - ArtifactStore          |
            |                      |  - Store::EventLog        |
            v                      +---------------------------+
   +------------------+
   |  Arcp::Transport |   Memory | Stdio | WebSocket
   +------------------+
```

### Layered responsibilities

| Layer        | Files                                                        | Notes                                                              |
| ------------ | ------------------------------------------------------------ | ------------------------------------------------------------------ |
| Envelope     | `lib/arcp/envelope.rb`, `lib/arcp/json.rb`                   | `Data.define`, structural equality, JSON encode/decode             |
| Errors       | `lib/arcp/error.rb`, `lib/arcp/error_code.rb`                | Canonical taxonomy as frozen constants; subclass per code          |
| Messages     | `lib/arcp/messages/*.rb`                                     | Each wire type → `Data.define` payload, registered                 |
| Transport    | `lib/arcp/transport/*.rb`                                    | Memory (tests), stdio, WebSocket                                   |
| Runtime      | `lib/arcp/runtime/*.rb`                                      | Per-session managers + dispatcher                                  |
| Client       | `lib/arcp/client/client.rb`                                  | Synchronous-style API on the same fiber reactor                    |
| Storage      | `lib/arcp/store/event_log.rb`                                | SQLite event log + idempotency table                               |
| CLI          | `lib/arcp/cli.rb`, `exe/arcp`                                | `dry-cli` commands                                                 |

## Concurrency model

Ruby has no algebraic data types and no compile-time exhaustiveness
check. We close those gaps with:

- **`Data.define`** for envelope, IDs, and message payloads — immutable
  value objects with structural equality.
- **`case/in` pattern matching** for typed dispatch on payload class.
- **The `async` gem** for fiber-based concurrency: synchronous-style
  code suspends on IO, with structured concurrency baked into the task
  tree.
- **`Async::Notification`** for one-shot wait/signal across fibers
  (used by `PendingRegistry`).
- **`Fiber[:arcp_trace]`** for trace context propagation (§17.1).

See [PLAN.md](PLAN.md) for the per-section plan and design notes.

## Samples

Each sample is self-contained: it spawns an in-memory runtime + client
and exercises one feature.

| File                                       | Demonstrates                                       |
| ------------------------------------------ | -------------------------------------------------- |
| `samples/01_minimal_session.rb`            | Handshake, ping/pong, close                        |
| `samples/02_tool_invoke_with_progress.rb`  | `tool.invoke` with `job.progress` + a text stream  |
| `samples/03_human_input_request.rb`        | `human.input.request` with schema validation       |
| `samples/04_permission_challenge.rb`       | `permission.request` → `permission.grant` → lease  |
| `samples/05_observer_subscription.rb`      | Subscribe, observe events, hit backfill marker     |
| `samples/06_relay_human_in_the_loop.rb`    | Combined human input + permission relay flow       |

## RFC mapping

| RFC §  | Implementation                                            | Status                          |
| -----  | --------------------------------------------------------- | ------------------------------- |
| §6     | `Arcp::Envelope`, `Arcp::Json`                            | Full                            |
| §7     | `Arcp::Capabilities`                                      | Full                            |
| §8     | `Arcp::Auth::{Bearer,Jwt}`, `Arcp::Runtime::SessionNegotiator` | `bearer`, `signed_jwt`, `none`; `mtls`/`oauth2` deferred |
| §9     | `SessionContext`                                          | Stateless + stateful; durable across reconnect deferred |
| §10    | `JobManager`                                              | Heartbeats, cancellation, interrupts; scheduled jobs deferred |
| §11    | `StreamManager`                                           | Base64 in-envelope only; sidecar deferred              |
| §12    | `SessionHelper#request_human_input`                       | Includes default + expiration                          |
| §13    | `SubscriptionManager`                                     | Filter, backfill, `subscription.backfill_complete`     |
| §14    | —                                                          | Out of scope for v0.1                                  |
| §15    | `LeaseManager`, `SessionHelper#request_permission`        | Trust elevation deferred                               |
| §16    | `ArtifactStore`                                           | Inline base64 only                                     |
| §17    | `Tracing`, `Messages::Telemetry::*`                       | `log`, `metric`, `trace.span`                          |
| §18    | `Arcp::Error*`                                            | Full canonical taxonomy                                |
| §19    | `Runtime#handle_resume`                                   | Message-id resume only; checkpoint deferred            |
| §21    | `Arcp::Extensions`, `Arcp::ExtensionRegistry`             | Full                                                   |
| §22    | `Arcp::Transport::{Memory,Stdio,Websocket}`               | WebSocket + stdio mandatory; HTTP/2 + QUIC deferred    |

## Running the test suite

```sh
bundle exec rspec --format documentation
bundle exec rubocop
bundle exec yard --fail-on-warning
bundle exec rake build
```

The relay scenario at `spec/e2e/relay_scenario_spec.rb` runs the same
flow over the memory and stdio transports as a shared example.

## License

Apache-2.0.
