# capability_negotiation

LiteLLM-style router selecting peer model-serving runtimes by their
advertised capabilities (cost, latency, model class), with ordered
fallback on `RESOURCE_EXHAUSTED` / `UNAVAILABLE`. Cost rolls up via
the standard `cost.usd` metric.

## Before ARCP

Static `model -> provider` map in YAML. Cost / latency tracked in a
separate per-provider sidecar dashboard. The router has no idea which
provider 429s right now, so retries spray across already-saturated
endpoints. Per-tenant cost reporting requires a third pipeline.

## With ARCP

```ruby
profiles[name] = profile_from(c.open[:capabilities])
chain = candidate_chain(profiles, 'balanced')
reply = invoke_with_fallback(
  clients: clients, chain: chain,
  tool: 'chat.completion', arguments: { ... },
  trace_id: trace_id
)
```

Peer selection is data-driven from the negotiated capabilities — no
sidecar config. Per-call cost lands on the meter via `cost.usd`
metrics, keyed by tenant + peer.

## ARCP primitives

- Capability extensions on the session — RFC §7, §21.
- `tool.invoke` / `tool.error` — §6.3.
- Canonical retry classification — §18.3.
- Standard metric names (`tokens.used`, `cost.usd`) — §17.3.1.
- Envelope `extensions` for per-call routing context — §6.1.

## File tour

- `main.rb` — open all peers, route one request, print rollup.
  Contains `Profile`, `candidate_chain`, `invoke_with_fallback`,
  `consume_metric`.

## Variations

- Push fallback chains to a remote policy service.
- Add a `quality` axis (offline eval scores) and weight selection.
- Re-emit the chosen peer + cost back to a billing topic for
  per-call chargeback.
