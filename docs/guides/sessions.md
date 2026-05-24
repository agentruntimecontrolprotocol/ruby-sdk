---
title: Sessions
sdk: ruby
kind: guide
order: 10
spec_sections: [§6.1, §6.2]
---

# Sessions

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
client = Arcp::Client.open(
  transport:    transport,
  auth:         { 'scheme' => 'bearer', 'token' => 'demo' },
  capabilities: caps
)
client.session.supports?(Arcp::Session::Feature::LIST_JOBS) # => true
client.session.capabilities.agents # => Arcp::Session::AgentInventory
```

The post-welcome snapshot is an `Arcp::Session::Info` value: `id`,
`runtime_version`, `capabilities` (intersected), `agents` (the runtime's
inventory), `heartbeat_interval_sec`, `resume_token`, `resume_window_sec`.

## Lifecycle

- `opening` — `session.hello` sent, awaiting reply
- `open` — `session.welcome` received, normal traffic
- `closing` — local `close()` called, `session.bye` sent
- `closed` — transport closed, all queues drained

`session.error` at any stage maps to one of `Arcp::Errors::*` and is
raised from `Client.open` or the current call.

## Capability negotiation

A session's `CapabilitySet` advertises `features`, `encodings`, and
(server-side) an `AgentInventory`. The handshake intersects client and
server sets; the result is stored on `client.session.capabilities`.

### Feature constants

```ruby
Arcp::Session::Feature::HEARTBEAT         # 'heartbeat'
Arcp::Session::Feature::ACK               # 'ack'
Arcp::Session::Feature::LIST_JOBS         # 'list_jobs'
Arcp::Session::Feature::SUBSCRIBE         # 'subscribe'
Arcp::Session::Feature::LEASE_EXPIRES_AT  # 'lease_expires_at'
Arcp::Session::Feature::COST_BUDGET       # 'cost.budget'
Arcp::Session::Feature::PROGRESS          # 'progress'
Arcp::Session::Feature::RESULT_CHUNK      # 'result_chunk'
Arcp::Session::Feature::AGENT_VERSIONS    # 'agent_versions'
Arcp::Session::Feature::MODEL_USE         # 'model.use'
Arcp::Session::Feature::PROVISIONED_CREDENTIALS # 'provisioned_credentials'
```

`Arcp::Session::Feature::ALL` is a frozen Array of all eleven.

### CapabilitySet

```ruby
caps = Arcp::Session::CapabilitySet.local(
  features:  [Arcp::Session::Feature::HEARTBEAT, Arcp::Session::Feature::LIST_JOBS],
  encodings: %w[utf8 base64]
)

caps.supports?(Arcp::Session::Feature::LIST_JOBS) # => true
caps.to_h
# => { 'features' => ['heartbeat', 'list_jobs'], 'encodings' => ['utf8', 'base64'] }
```

### Negotiation example

```ruby
client_caps = Arcp::Session::CapabilitySet.local(
  features:  ['heartbeat', 'list_jobs'],
  encodings: ['utf8']
)
server_caps = Arcp::Session::CapabilitySet.local(
  features:  ['heartbeat', 'subscribe'],
  encodings: ['utf8', 'base64']
)

effective = client_caps.intersect(server_caps)
effective.features  # ['heartbeat']  -- intersection
effective.encodings # ['utf8']       -- intersection
```

`Arcp::Client.open` performs this intersection automatically and stores
the result on `client.session.capabilities`.

### Checking a feature

```ruby
if client.session.supports?(Arcp::Session::Feature::SUBSCRIBE)
  client.subscribe_job(job_id: id, history: true, from_event_seq: 0)
end
```

Calling a feature method without the negotiated capability raises
`Arcp::Errors::UnnegotiatedFeature`.

## See also

- `guides/auth.md`
- `guides/resume.md`
