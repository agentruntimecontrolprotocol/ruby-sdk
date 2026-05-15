---
title: Resume
sdk: ruby
kind: concept
order: 17
spec_sections: [§6.3]
---

# Resume

## What

After a transport drop, a client may reconnect and continue receiving
events for in-flight jobs. The mechanism is two pieces of state on
`session.welcome`: a `resume_token` and a `resume_window_sec`.

## Resume token

```ruby
client = Arcp::Client.open(transport: transport, auth: auth)
token = client.session.resume_token
window = client.session.resume_window_sec
```

Save `token` somewhere durable across reconnects. The runtime guarantees
the resume window for that token.

## Reconnect with last_event_seq

```ruby
new_client = Arcp::Client.open(
  transport: new_transport,
  auth: auth,
  resume: { 'token' => token, 'last_event_seq' => { job_id => last_seq } }
)
```

The runtime replays every job-event with `event_seq > last_seq` from
its event log, then resumes live tailing.

## Resume window

If the `resume_window_sec` has elapsed since the prior session closed,
the runtime responds with `session.error` code
`RESUME_WINDOW_EXPIRED`. The client raises
`Arcp::Errors::ResumeWindowExpired` from `Client.open`. Recover by
opening a fresh session and re-subscribing with `history: true`.

## See also

- `concepts/heartbeats.md`
- `concepts/subscribe.md`
