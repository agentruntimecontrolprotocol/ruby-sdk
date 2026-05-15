---
title: Heartbeats
sdk: ruby
kind: concept
order: 14
spec_sections: [§6.4]
---

# Heartbeats

## What

`session.ping` and `session.pong` keep idle connections alive and surface
half-open TCP states. The runtime advertises a `heartbeat_interval_sec`
on welcome; the client schedules a ping at that cadence.

## Cadence

If the negotiated capabilities include `heartbeat` and
`heartbeat_interval_sec` is non-nil, the client starts a heartbeat fiber
that sends `session.ping` every interval. Any inbound envelope counts as
liveness — explicit pongs are sent in reply to pings but are otherwise
not required.

## In Ruby

```ruby
runtime = Arcp::Runtime::Runtime.new(
  auth_verifier: verifier,
  heartbeat_interval_sec: 30  # nil to disable
)
client = Arcp::Client.open(transport: t, auth: auth)
client.session.heartbeat_interval_sec # => 30
```

## HEARTBEAT_LOST

If a peer detects N consecutive missed heartbeats it MAY close the
transport and raise `Arcp::Errors::HeartbeatLost`. This error is
`retryable? == true`.

A lost heartbeat MUST NOT terminate running jobs at the runtime. Job
state persists in the event log within the resume window; reconnecting
clients can resume via `resume_token` and `from_event_seq`.

## See also

- `concepts/resume.md`
- `concepts/sessions.md`
