---
title: Capabilities
sdk: ruby
kind: reference
order: 51
spec_sections: [§6.2]
---

# Capabilities

A session's `CapabilitySet` advertises `features`, `encodings`, and
(server-side) an `AgentInventory`. The handshake intersects client and
server sets; the result is `session.capabilities`.

## Feature constants

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
```

`Arcp::Session::Feature::ALL` is a frozen Array of all nine.

## CapabilitySet

```ruby
caps = Arcp::Session::CapabilitySet.local(
  features: [Arcp::Session::Feature::HEARTBEAT, Arcp::Session::Feature::LIST_JOBS],
  encodings: %w[utf8 base64]
)

caps.supports?(Arcp::Session::Feature::LIST_JOBS) # => true
caps.to_h
# => { 'features' => ['heartbeat', 'list_jobs'], 'encodings' => ['utf8', 'base64'] }
```

## Negotiation

```ruby
client_caps = Arcp::Session::CapabilitySet.local(features: ['heartbeat', 'list_jobs'], encodings: ['utf8'])
server_caps = Arcp::Session::CapabilitySet.local(features: ['heartbeat', 'subscribe'], encodings: ['utf8', 'base64'])

effective = client_caps.intersect(server_caps)
effective.features  # ['heartbeat']  -- intersection
effective.encodings # ['utf8']       -- intersection
```

The `Arcp::Client.open` flow performs this intersection automatically
and stores the result on `client.session.capabilities`.

## Checking a feature

```ruby
if client.session.supports?(Arcp::Session::Feature::SUBSCRIBE)
  client.subscribe_job(job_id: id, history: true, from_event_seq: 0)
end
```

Calling a feature method without the negotiated capability raises
`Arcp::Errors::UnnegotiatedFeature`.
