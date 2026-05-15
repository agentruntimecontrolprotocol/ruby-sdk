---
title: Events
sdk: ruby
kind: concept
order: 13
spec_sections: [§8]
---

# Events

## What

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

## See also

- `guides/result-streaming.md`
- `concepts/vendor-extensions.md`
