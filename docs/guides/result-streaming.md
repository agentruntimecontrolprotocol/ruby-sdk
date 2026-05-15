---
title: Result streaming
sdk: ruby
kind: guide
order: 22
spec_sections: [§8.4]
---

# Result streaming

For results that don't fit comfortably in a single `job.result` payload,
emit `result_chunk` events and a terminal `job.result` carrying just the
`result_id` + `result_size`.

## Producer side

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

## Encoding

Pass `encoding: 'base64'` for binary payloads:

```ruby
ctx.stream_result(encoding: 'base64') do |writer|
  writer.write(File.binread('big.bin'), more: false)
end
```

The body's `decoded` helper handles either encoding on the consumer
side.

## Consumer side

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

## Backpressure

Each `writer.write` blocks until the runtime accepts the chunk for
publication. The runtime fans out to subscribers via the event log; slow
subscribers do not block the producer.
