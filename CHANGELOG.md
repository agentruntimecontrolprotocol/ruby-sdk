# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.0]

### Added

- `Arcp::Envelope` per spec §5.1 (arcp, id, type, session_id, trace_id, job_id, event_seq, payload).
- `Arcp::Client` with session handshake, `submit_job`, `subscribe_job`, `cancel_job`, `get_result`, `list_jobs`, `ack`, `close`.
- `Arcp::Runtime::Runtime` with agent registry, job manager, lease manager, subscription manager, event log.
- `Arcp::Runtime::JobContext` with `progress`, `log`, `metric`, `status`, `tool_call`, `tool_result`, `stream_result`, `finish`, `fail!`, `emit`.
- Session handshake: `session.hello`, `session.welcome`, `session.bye`, `session.error` (§6.1, §6.7).
- Capability negotiation via `Arcp::Session::CapabilitySet` and `Arcp::Session::Feature` constants (§6.2).
- Heartbeat with `session.ping` / `session.pong` (§6.4).
- Application-level ack with `session.ack` (§6.5).
- Cursored `session.list_jobs` / `session.jobs` (§6.6).
- Resume token and `last_event_seq` replay (§6.3).
- Agent versioning with `name@version` refs and `AgentInventory.resolve` (§7.5).
- Cross-session `job.subscribe` with history replay (§7.6).
- `result_chunk` event kind with `result_id` terminator (§8.4).
- All ten standard event kinds: progress, result_chunk, log, thought, tool_call, tool_result, status, metric, trace_span, delegate (§8.2).
- Lease subsetting with capability/expires_at/budget bounds (§9, §10).
- `cost.budget` capability using `BigDecimal` arithmetic (§9.6).
- Trace context propagation via Fiber-local `Arcp::Trace::Context` (§11).
- Transports: `MemoryTransport`, `WebSocketTransport`, `StdioTransport`.
- 15 wire error codes mapped to `Arcp::Errors::*` subclasses (§12).
- Pluggable `Arcp::Auth::AuthScheme` with bundled `Bearer` verifier.
- Vendor extension namespace via `x-vendor.*` event kinds (§15).
