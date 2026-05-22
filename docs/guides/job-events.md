---
title: Job events
sdk: ruby
kind: guide
order: 21
spec_sections: [§8, §7.6]
---

# Job events

A `job.event` envelope carries one `Arcp::Job::Event { kind, body }`
plus a monotonic `event_seq`. Events are ordered per-job and replayed
verbatim from the runtime's event log on subscribe-with-history.

## EventKind

```
progress      EventBody::Progress    current, total, units, message
result_chunk  EventBody::ResultChunk result_id, chunk_seq, data, encoding, more
log           EventBody::Log         level, message, fields
thought       EventBody::Thought     text
tool_call     EventBody::ToolCall    call_id, tool, args
tool_result   EventBody::ToolResult  call_id, result, error
status        EventBody::Status      phase, message
metric        EventBody::Metric      name, value, unit
trace_span    EventBody::TraceSpan   span_id, name, started_at, ended_at, attributes
delegate      EventBody::Delegate    child_job_id, agent, lease
```

Unknown kinds (e.g. `x-vendor.acme.progress`) round-trip as a frozen
`Hash` body.

## Pattern-match dispatch

```ruby
handle.subscribe(client: client).each do |event|
  case event
  in { kind: Arcp::Job::EventKind::PROGRESS, body: { current:, total: } }
    puts "#{current}/#{total}"
  in { kind: Arcp::Job::EventKind::LOG, body: { level:, message: } }
    puts "[#{level}] #{message}"
  in { kind: Arcp::Job::EventKind::RESULT_CHUNK, body: }
    write_chunk(body.decoded)
  else
    # ignore unknown / vendor kinds
  end
end
```

## Subscribe

`subscribe_job` lets any session — including a session other than the
one that submitted the job — observe a job's event stream. With
`history: true` and `from_event_seq: 0`, the runtime replays the event
log from the start before tailing live events.

### Cross-session observation

```ruby
# Session A submits
handle = client_a.submit_job(agent: 'worker')

# Session B observes
events = client_b.subscribe_job(
  job_id:         handle.job_id,
  history:        true,
  from_event_seq: 0
).take(3)
```

### History replay

The runtime maintains an `EventLog` with a `resume_window_sec` retention.
Replay is sourced from this log; events evicted past the window are not
recoverable. Subscribe before that window elapses, or accept partial replay.

### No cancel from a subscriber

A subscriber handle observes but cannot cancel. Cancellation is reserved
for the session that owns the job — calling `cancel_job` on an
observer-side handle raises a permission error from the runtime.

## Result streaming

For results that don't fit comfortably in a single `job.result` payload,
emit `result_chunk` events and a terminal `job.result` carrying just the
`result_id` + `result_size`.

### Producer side

```ruby
HANDLER = lambda do |ctx|
  ctx.stream_result(encoding: 'utf8') do |writer|
    30.times { |i| writer.write("chunk #{i}\n", more: i < 29) }
  end
  ctx.finish
end
```

`stream_result` allocates a `result_id`, then for each `writer.write`
emits an `Arcp::Job::EventKind::RESULT_CHUNK` event with monotonic
`chunk_seq`. The final chunk passes `more: false`. `ctx.finish` with no
`result:` argument terminates the job; the `job.result` envelope carries
the `result_id` and `result_size` so clients can verify completeness.

Mixing `stream_result` with `ctx.finish(result: ...)` raises
`Arcp::Errors::ProtocolViolation`.

### Encoding

Pass `encoding: 'base64'` for binary payloads:

```ruby
ctx.stream_result(encoding: 'base64') do |writer|
  writer.write(File.binread('big.bin'), more: false)
end
```

The body's `decoded` helper handles either encoding on the consumer side.

### Consumer side

```ruby
handle = client.submit_job(agent: 'streamer')
chunks = handle.subscribe(client: client).select do |ev|
  ev.kind == Arcp::Job::EventKind::RESULT_CHUNK
end
assembled = chunks.map { |ev| ev.body.decoded }.join

result = handle.get_result(client: client)
result.result_id   # matches chunks.first.body.result_id
result.result_size # total bytes written
```

### Backpressure

Each `writer.write` blocks until the runtime accepts the chunk for
publication. The runtime fans out to subscribers via the event log; slow
subscribers do not block the producer.

## See also

- `guides/jobs.md`
- `guides/vendor-extensions.md`
- `guides/resume.md`
