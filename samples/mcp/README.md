# mcp

ARCP runtime that fronts an MCP server. Inbound `tool.invoke`
envelopes translate to MCP `call_tool`; the bridge emits the ARCP
job lifecycle back to the calling client.

## Before ARCP

You either (a) ditch your ARCP-native session/lease/observability
story and run MCP straight, losing the runtime layer; or (b) embed
MCP into one specific agent that knows how to call it directly,
which doesn't compose with the rest of your stack. Wrap one,
re-wrap the other.

## With ARCP

Per RFC §20:

| MCP         | ARCP                                    |
|-------------|-----------------------------------------|
| tool schema | capability (`arcpx.mcp.tool.<name>.v1`) |
| tool call   | job (`tool.invoke` → `job.completed`)   |
| resource    | stream of `kind: event` (delegated)     |

The bridge advertises the upstream server's tools as namespaced
capability extensions at session open. Clients that need a specific
MCP tool refuse the session if it's not advertised — same shape as
any other ARCP capability negotiation.

```ruby
MCP::Client.stdio(Upstream.params) do |mcp|
  mcp.initialize!
  extensions = advertise_from_mcp(mcp) # MCP tool list
  inbound.each do |envelope|
    handle_invoke(send_envelope, mcp: mcp, request: envelope) if envelope.type == 'tool.invoke'
  end
end
```

`call_via_mcp` translates MCP errors into canonical ARCP error
codes (`FAILED_PRECONDITION` for `result.is_error`, `INTERNAL` for
unexpected exceptions at the boundary).

## ARCP primitives

- MCP compatibility — RFC §20 (the whole point).
- `tool.invoke` / `job.accepted` / `job.started` / `job.completed`
  / `job.failed` lifecycle — §6.3, §10.
- Capability extensions for advertised tools — §7, §21.
- Canonical error mapping — §18.2.

## File tour

- `main.rb` — the bridge. `handle_invoke` is the file. Runtime
  wiring (transport, session manager) is symmetric with
  `Arcp::Runtime::Runtime` and elided.
- `upstream.rb` — MCP server invocation (`StdioParams`). The MCP gem
  import is stubbed pending a stable `mcp-rb` release.

## Variations

- Front multiple MCP servers from one ARCP runtime; namespace each
  set of tools under `arcpx.mcp.<server>.tool.<name>.v1`.
- Bridge MCP resources to ARCP streams of `kind: event` so ARCP
  observers can subscribe to MCP resource changes.
- Layer ARCP leases on top: gate `tool.invoke` for any
  side-effecting MCP tool through `permission.request` before
  forwarding to MCP.
