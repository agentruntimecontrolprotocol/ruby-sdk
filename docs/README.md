---
title: Documentation
sdk: ruby
kind: index
order: 0
---

# ARCP Ruby SDK documentation

## Start here

| Doc | Description |
| --- | --- |
| [Getting started](getting-started.md) | Install, minimal in-process example, first job |
| [Transports](transports.md) | MemoryTransport, WebSocketTransport, StdioTransport |
| [Architecture](architecture.md) | Namespace map, concurrency model, event flow |
| [Troubleshooting](troubleshooting.md) | Common errors and fixes |

## Guides

| Guide | Spec | Description |
| --- | --- | --- |
| [Sessions](guides/sessions.md) | §6.1–§6.2 | Session lifecycle, wire shape, capability negotiation |
| [Authentication](guides/auth.md) | §6.1 | Bearer verifier, custom AuthScheme |
| [Resume](guides/resume.md) | §6.3–§6.4 | Transport reconnect, resume token, heartbeats |
| [Jobs](guides/jobs.md) | §7, §9.6 | FSM, Handle API, idempotency, cancellation, cost budgets |
| [Job events](guides/job-events.md) | §8, §7.6 | EventKind table, pattern-match dispatch, subscribe, result streaming |
| [Leases](guides/leases.md) | §9 | Capabilities, expires_at, cost.budget, model.use, subsetting |
| [Delegation](guides/delegation.md) | §10, §9.4 | Delegate event, child lease subset rules |
| [Agent versioning](architecture.md#agent-versioning) | §7.5 | name@version pins, AgentVersionNotAvailable |
| [Provisioned credentials](guides/credentials.md) | §9.7–§9.8 | InMemoryProvisioner, lease-scoped keys, rotation/revocation |
| [Deployment](guides/deployment.md) | — | Falcon + WebSocket, process supervision |
| [Observability](guides/observability.md) | §11 | Trace::Context, OpenTelemetry bridge |
| [Errors](guides/errors.md) | §12 | Wire codes table, Arcp::Errors.for, retryable? |
| [Vendor extensions](guides/vendor-extensions.md) | §15 | x-vendor.* kinds, emit and receive |
| [Recipes](recipes.md) | — | Common patterns (submit, stream, cancel, budgets, credentials, resume) |

## Diagrams

| File | Description |
| --- | --- |
| [diagrams/session-fsm-light.svg](diagrams/session-fsm-light.svg) | Session lifecycle state machine |
| [diagrams/job-fsm-light.svg](diagrams/job-fsm-light.svg) | Job lifecycle state machine |
| [diagrams/capability-negotiation-light.svg](diagrams/capability-negotiation-light.svg) | Capability negotiation handshake |
| [diagrams/heartbeat-flow-light.svg](diagrams/heartbeat-flow-light.svg) | Heartbeat ping/pong flow |
| [diagrams/result-chunk-sequence-light.svg](diagrams/result-chunk-sequence-light.svg) | Result streaming chunk sequence |
| [diagrams/module-deps-light.svg](diagrams/module-deps-light.svg) | Module dependency graph |

Generate diagrams from source:

```
bash bin/render-diagrams.sh
```

## CLI

There is no standalone CLI for this SDK. Runtime management and transport
operations are performed through the Ruby API. See `getting-started.md`
and `guides/deployment.md`.

## Conformance

See [conformance.md](conformance.md) for the full spec-to-code matrix.
