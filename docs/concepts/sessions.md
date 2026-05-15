---
title: Sessions
sdk: ruby
kind: concept
order: 10
spec_sections: [§6.1, §6.2]
---

# Sessions

## What

A session is the unit of authenticated, capability-negotiated connection
between one client and one runtime. The client sends `session.hello`,
the runtime responds with `session.welcome`, and from that point all
subsequent envelopes carry the same `session_id`.

## Wire shape

```json
// session.hello
{ "type": "session.hello",
  "payload": {
    "client_name": "my-app",
    "client_version": "1.2.3",
    "auth": { "scheme": "bearer", "token": "..." },
    "capabilities": { "features": ["heartbeat","ack","list_jobs"], "encodings": ["utf8","base64"] }
  }
}

// session.welcome
{ "type": "session.welcome",
  "payload": {
    "runtime_version": "1.0.0",
    "capabilities": { "features": [...], "encodings": [...], "agents": [...] },
    "heartbeat_interval_sec": 30,
    "resume_token": "...",
    "resume_window_sec": 300
  }
}
```

## In Ruby

```ruby
caps = Arcp::Session::CapabilitySet.local(
  features: [Arcp::Session::Feature::HEARTBEAT,
             Arcp::Session::Feature::LIST_JOBS,
             Arcp::Session::Feature::SUBSCRIBE]
)
client = Arcp::Client.open(transport: transport, auth: { 'scheme' => 'bearer', 'token' => 'demo' }, capabilities: caps)
client.session.supports?(Arcp::Session::Feature::LIST_JOBS) # => true
client.session.capabilities.agents # => Arcp::Session::AgentInventory
```

The post-welcome snapshot is an `Arcp::Session::Info` value: `id`,
`runtime_version`, `capabilities` (intersected), `agents` (the runtime's
inventory), `heartbeat_interval_sec`, `resume_token`,
`resume_window_sec`.

## Lifecycle

- `opening` — `session.hello` sent, awaiting reply
- `open` — `session.welcome` received, normal traffic
- `closing` — local `close()` called, `session.bye` sent
- `closed` — transport closed, all queues drained

`session.error` at any stage maps to one of `Arcp::Errors::*` and is
raised from `Client.open` or the current call.

## See also

- `concepts/auth.md`
- `concepts/heartbeats.md`
- `reference/capabilities.md`
