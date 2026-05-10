# ARCP Ruby SDK — Conformance

This document tracks per-RFC-section conformance for the `arcp` Ruby
SDK against [`RFC-0001-v2.md`](RFC-0001-v2.md).

> **Scope:** v0.1.0. Items marked **Deferred** raise
> `Arcp::Error::Unimplemented` with the corresponding RFC section.

| Section | Status   | Notes                                                                             |
| ------- | -------- | --------------------------------------------------------------------------------- |
| §6.1 Envelope                  | Full         | `Data.define` value object; `to_wire_hash` omits nils                  |
| §6.4 Delivery semantics        | Partial      | Idempotency key persisted in `arcp_idempotency` table                  |
| §6.5 Priority and QoS          | Partial      | Constants and filter-side respect; runtime-side scheduling not adaptive |
| §7   Capability negotiation    | Full         | `Capabilities.normalize` and `Capabilities.negotiate`                  |
| §8.2 Bearer auth               | Full         | `Arcp::Auth::Bearer`                                                   |
| §8.2 mTLS                      | Deferred     | Returns `session.rejected` with `code: UNIMPLEMENTED`                  |
| §8.2 OAuth2                    | Deferred     | Returns `session.rejected` with `code: UNIMPLEMENTED`                  |
| §8.2 signed_jwt                | Full         | `Arcp::Auth::Jwt`; algorithms whitelist required                       |
| §8.2 none                      | Full         | Only when both sides advertise `anonymous: true`                       |
| §8.4 Re-authentication         | Partial      | `session.refresh` schema only; runtime-side trigger not implemented    |
| §9   Sessions                  | Partial      | Stateless + stateful; durable across reconnect deferred                |
| §10.2 Job state machine        | Full         | `JobState`, `JobRecord#transition!`                                    |
| §10.3 Heartbeats               | Partial      | Manual emission via `JobContext#heartbeat`; passive watchdog deferred  |
| §10.4 Cancellation             | Full         | `cancel.accepted` + cooperative `task.stop`                            |
| §10.5 Interrupts               | Full         | Job → `:blocked`, runtime emits `human.input.request`                  |
| §10.6 Scheduled jobs           | Deferred     | `nack UNIMPLEMENTED`                                                   |
| §11.1 Stream kinds             | Full         | text/binary/event/log/metric/thought                                   |
| §11.3 Binary encoding          | Partial      | Inline base64 only; sidecar deferred                                   |
| §12.1 Input requests           | Full         | Schema validated via `json_schemer`                                    |
| §12.2 Choice requests          | Full         | `human.choice.request/response` payloads                               |
| §12.3 Multi-channel resolution | Partial      | First-response-wins only; quorum policies deferred                     |
| §12.4 Expiration               | Full         | Default fallback or `human.input.cancelled` per spec                   |
| §13   Subscriptions            | Full         | Filter, backfill, `subscription.backfill_complete`, fan-out            |
| §14   Multi-agent              | Deferred     | Out of scope for v0.1                                                  |
| §15.1 Permission model         | Full         | Permission strings carried opaque                                      |
| §15.4 Permission challenge     | Full         | `request_permission` → grant/deny → lease                              |
| §15.5 Lease lifecycle          | Full         | `lease.granted/extended/revoked` + `validate!`                         |
| §15.6 Trust elevation          | Deferred     | `Unimplemented`                                                        |
| §16   Artifacts                | Partial      | Inline base64; in-memory store with sweep                              |
| §17.1 Tracing                  | Full         | Fiber-local trace context                                              |
| §17.2 Structured logs          | Full         | `log` payload                                                          |
| §17.3 Metrics                  | Full         | `metric` payload + standard names as constants                         |
| §18   Error model              | Full         | Canonical taxonomy and exception hierarchy                             |
| §19   Resumability             | Partial      | Message-id resume; checkpoint deferred                                 |
| §20   MCP compatibility        | Documented   | No code; mapping in README                                             |
| §21   Extensions               | Full         | `arcpx.*` and reverse-DNS namespaces; `x-` rejected                    |
| §22   Transports               | Partial      | WebSocket + stdio mandatory; HTTP/2 + QUIC deferred                    |

## Open interpretation choices

These are documented in detail in [PLAN.md §5](PLAN.md):

1. The runtime ignores envelope `target` for routing (§6.1).
2. Absent non-boolean capabilities fall back to runtime defaults (§7).
3. `session.close` cancels open jobs unless `payload.detach: true` (§9).
4. `payload.sequence` is monotonic per `stream_id` for all stream
   kinds, not just binary (§11.3).
5. JSON wire decoding only symbolizes top-level envelope and payload
   keys; nested user data preserves the original (string) keys.
