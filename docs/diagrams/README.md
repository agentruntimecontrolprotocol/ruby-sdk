# Arcp Ruby SDK — architecture diagrams

Paired light/dark Graphviz diagrams that GitHub auto-switches via
`<picture>` and `prefers-color-scheme`. Source is `.dot`; commit both the
`.dot` and rendered `.svg` files.

## Index

| Diagram | Purpose |
| --- | --- |
| [`module-deps`](module-deps-light.dot) | Module dependency graph: client surface, transport, runtime internals. |
| [`session-fsm`](session-fsm-light.dot) | Client-side `Arcp::Session` state machine from `init` through `live` to terminal states (spec §6.2 §6.4 §6.7). |
| [`job-fsm`](job-fsm-light.dot) | `Arcp::Job` lifecycle from `submit_sent` through `running` to success / error terminals (spec §7 §8 §9 §12). |
| [`capability-negotiation`](capability-negotiation-light.dot) | Two-lane sequence of `session.hello` / `session.welcome` capability intersection (spec §6.2). |
| [`result-chunk-sequence`](result-chunk-sequence-light.dot) | Three-lane sequence (agent → runtime → client) for `result_chunk` streaming and terminal `job.result` (spec §8.4). |
| [`heartbeat-flow`](heartbeat-flow-light.dot) | Two-lane ping/pong cycles plus the `HEARTBEAT_LOST` failure branch (spec §6.4). |

## Render

```bash
dot -Tsvg docs/diagrams/<name>-light.dot -o docs/diagrams/<name>-light.svg
dot -Tsvg docs/diagrams/<name>-dark.dot  -o docs/diagrams/<name>-dark.svg
```

## Embed

```markdown
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/diagrams/<name>-dark.svg">
  <img alt="<description>" src="docs/diagrams/<name>-light.svg">
</picture>
```

GitHub serves the matching SVG based on the viewer's theme. Both
variants render with `bgcolor="transparent"`, so they sit on whatever
page background is active.
