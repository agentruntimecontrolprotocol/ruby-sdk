---
title: Resume
sdk: ruby
kind: guide
order: 12
spec_sections: [§6.3, §6.4]
---

# Resume

After a transport drop, a client may reconnect and continue receiving
events for in-flight jobs. The mechanism is two pieces of state on
`session.welcome`: a `resume_token` and a `resume_window_sec`.

## Resume token

```ruby
client = Arcp::Client.open(transport: transport, auth: auth)
token  = client.session.resume_token
window = client.session.resume_window_sec
```

Save `token` somewhere durable across reconnects. The runtime guarantees
the resume window for that token.

## Reconnect with last_event_seq

```ruby
new_client = Arcp::Client.open(
  transport: new_transport,
  auth:      auth,
  resume:    {
    'token'         => token,
    'last_event_seq' => { job_id => last_seq }
  }
)
```

The runtime replays every job-event with `event_seq > last_seq` from
its event log, then resumes live tailing.

## Resume window expiry

If `resume_window_sec` has elapsed since the prior session closed, the
runtime responds with `session.error` code `RESUME_WINDOW_EXPIRED`. The
client raises `Arcp::Errors::ResumeWindowExpired` from `Client.open`.
Recover by opening a fresh session and re-subscribing with `history: true`.

## Heartbeats and reconnect

`session.ping` / `session.pong` keep idle connections alive and surface
half-open TCP states. The runtime advertises a `heartbeat_interval_sec`
on welcome; the client schedules a ping at that cadence.

```ruby
runtime = Arcp::Runtime::Runtime.new(
  auth_verifier:          verifier,
  heartbeat_interval_sec: 30  # nil to disable
)
client = Arcp::Client.open(transport: t, auth: auth)
client.session.heartbeat_interval_sec # => 30
```

If a peer detects N consecutive missed heartbeats it MAY close the
transport and raise `Arcp::Errors::HeartbeatLost` (`retryable? == true`).

A lost heartbeat MUST NOT terminate running jobs at the runtime. Job
state persists in the event log within the resume window; reconnecting
clients can resume via `resume_token` and `from_event_seq`.

## See also

- `guides/sessions.md`
- `guides/jobs.md`
