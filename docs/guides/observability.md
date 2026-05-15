---
title: Observability
sdk: ruby
kind: guide
order: 40
spec_sections: [§11]
---

# Observability

ARCP carries a 32-hex `trace_id` on every envelope. The SDK exposes a
Fiber-local trace context and an OpenTelemetry bridge.

## trace_id propagation

`Arcp::Trace.current` returns the active `Arcp::Trace::Context`. The
client populates each outgoing envelope's `trace_id` from this context.
Inbound envelopes' `trace_id` is preserved in payload metadata.

```ruby
Arcp::Trace.with(trace_id: '0123456789abcdef0123456789abcdef') do
  handle = client.submit_job(agent: 'echo', input: { 'msg' => 'hi' })
  # All envelopes sent inside this block carry that trace_id.
end
```

## Span attributes

Recommended span attributes for outgoing spans:

- `arcp.session.id`
- `arcp.job.id`
- `arcp.agent` (resolved `name@version`)
- `arcp.lease.id`
- `arcp.lease.expires_at`
- `arcp.budget.remaining` (per currency)
- `arcp.event.kind` (on per-event spans)

## OpenTelemetry bridge

If `opentelemetry` is loaded, `Arcp::Trace.in_span(name, attributes:)`
delegates to the registered tracer:

```ruby
require 'opentelemetry/sdk'
OpenTelemetry::SDK.configure

Arcp::Trace.in_span('arcp.submit', attributes: { 'arcp.agent' => 'echo' }) do |span|
  client.submit_job(agent: 'echo', input: { 'msg' => 'hi' })
end
```

Without OpenTelemetry loaded, `in_span` falls back to a no-op that still
threads the trace context through Fiber-local state.

## Server-side spans

A handler may wrap its work in a span; attributes set on that span are
available to whatever tracer is configured by the host application.

```ruby
HANDLER = lambda do |ctx|
  Arcp::Trace.in_span('agent.echo.handle', attributes: { 'arcp.job.id' => ctx.job_id }) do
    ctx.finish(result: ctx.input)
  end
end
```
