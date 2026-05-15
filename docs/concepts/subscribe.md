---
title: Subscribe
sdk: ruby
kind: concept
order: 15
spec_sections: [§7.6]
---

# Subscribe

## What

`subscribe_job` lets any session — including a session other than the
one that submitted the job — observe a job's event stream. With
`history: true` and `from_event_seq: 0`, the runtime replays the event
log from the start before tailing live events.

## Cross-session observation

```ruby
# session A submits
handle = client_a.submit_job(agent: 'worker')

# session B observes
events = client_b.subscribe_job(
  job_id: handle.job_id,
  history: true,
  from_event_seq: 0
).take(3)
```

## History replay

The runtime maintains an `EventLog` with a `resume_window_sec` retention.
Replay is sourced from this log; events evicted past the window are not
recoverable. Subscribe before that window elapses, or accept partial
replay.

## No cancel from a subscriber

A subscriber handle observes but cannot cancel. Cancellation is reserved
for the session that owns the job — calling `cancel_job` on an
observer-side handle raises a permission error from the runtime.

## See also

- `concepts/jobs.md`
- `concepts/resume.md`
