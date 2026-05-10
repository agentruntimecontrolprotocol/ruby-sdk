# ARCP Ruby SDK — Conformance

This document tracks per-RFC-section conformance for the `arcp` Ruby
SDK against `RFC-0001-v2.md`.

> **Status:** placeholder during Phase 0. Each cell is filled in as the
> corresponding phase lands.

| Section | Status | Notes |
| --- | --- | --- |
| §6 Envelope | Pending | Phase 1 |
| §7 Capability negotiation | Pending | Phase 2 |
| §8 Authentication & identity | Partial (planned) | `bearer`, `signed_jwt`, `none` only; `mtls`/`oauth2` deferred |
| §9 Sessions | Partial (planned) | Stateless + stateful; durable across reconnect deferred |
| §10 Jobs | Partial (planned) | Scheduled jobs deferred |
| §11 Streaming | Partial (planned) | Base64 in-envelope only; sidecar deferred |
| §12 Human-in-the-loop | Pending | Phase 4 |
| §13 Subscriptions | Pending | Phase 5 |
| §14 Multi-agent | Deferred | Out of scope for v0.1 |
| §15 Permissions & leases | Partial (planned) | Trust elevation deferred |
| §16 Artifacts | Partial (planned) | Inline base64 only |
| §17 Observability | Pending | Phase 1+ |
| §18 Error model | Pending | Phase 1 |
| §19 Resumability | Partial (planned) | Message-id resume only; checkpoint deferred |
| §20 MCP compatibility | Documented | No code; mapping documented in README |
| §21 Extensions | Pending | Phase 1 |
| §22 Reference transports | Partial (planned) | WebSocket + stdio mandatory; HTTP/2 + QUIC deferred |
