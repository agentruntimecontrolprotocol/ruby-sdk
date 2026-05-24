---
title: Resume
sdk: ruby
kind: guide
order: 12
spec_sections: [§6.3, §6.4]
---

# Resume

The Ruby SDK exposes `resume_token` and `resume_window_sec` on
`session.welcome`, but it does not yet use the `resume:` reconnect
payload to transparently restore a dropped session. What is shipped
today is an in-memory replay window for job events and subscription
history.

## Replay retained events

When you need missed history, open a fresh session and subscribe with
`history: true`. Use `from_event_seq: 0` for a full replay of the
retained window.

```ruby
client = Arcp::Client.open(transport: transport, auth: auth)
handle = client.submit_job(agent: 'long-runner')

replay = client.subscribe_job(
  job_id: handle.job_id,
  history: true,
  from_event_seq: 0
)

replay.each do |event|
  puts "#{event.kind}: #{event.body.to_h}"
end
```

## Retention window

The runtime keeps buffered events in memory for the configured
`resume_window_sec` period and evicts older entries from the replay log.
If that window elapses before you subscribe, the older events are no
longer recoverable.

```ruby
runtime = Arcp::Runtime::Runtime.new(
  auth_verifier:          verifier,
  heartbeat_interval_sec: 30,  # nil to disable
  resume_window_sec:      300
)

client.session.resume_token
client.session.resume_window_sec
```

## Heartbeats

`session.ping` / `session.pong` keep idle connections alive and surface
half-open TCP states. The runtime advertises a
`heartbeat_interval_sec` on welcome; the client schedules a ping at that
cadence.

If a peer detects N consecutive missed heartbeats it MAY close the
transport and raise `Arcp::Errors::HeartbeatLost` (`retryable? == true`).

A lost heartbeat MUST NOT terminate running jobs at the runtime. Job
state persists in the event log within the replay window.

## See also

- `guides/sessions.md`
- `guides/job-events.md`
