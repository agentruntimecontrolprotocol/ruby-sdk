---
title: Jobs
sdk: ruby
kind: concept
order: 11
spec_sections: [§7]
---

# Jobs

## What

A job is one invocation of one agent within an open session. It has a
deterministic lifecycle: `job.submit` -> `job.accepted` -> stream of
`job.event` -> terminal `job.result` or `job.error`.

## FSM

```
submitted
  -> accepted        (runtime allocated job_id and lease)
  -> running         (first event emitted by handler)
  -> succeeded       (job.result terminal)
  -> failed          (job.error terminal)
  -> cancelled       (job.error with code=CANCELLED)
```

A job is terminal on `succeeded`, `failed`, or `cancelled`. Subscriptions
end at the terminal envelope. The `event_seq` on each `job.event` is
monotonic per-job, starting at 1.

## In Ruby

```ruby
handle = client.submit_job(
  agent: 'echo',
  input: { 'msg' => 'hi' },
  idempotency_key: 'req-42',
  max_runtime_sec: 60
)
handle.job_id        # String
handle.lease         # Arcp::Lease::Lease (issued by runtime)
handle.submitted_at  # ISO-8601 UTC

handle.subscribe(client: client).each { |ev| ... }
result = handle.get_result(client: client)
result.final_status  # 'success'
result.result        # whatever the handler passed to ctx.finish(result:)
```

## Idempotency

Submitting twice with the same `idempotency_key` resolves to the same
job_id. A different payload under an existing key raises
`Arcp::Errors::DuplicateKey`.

## See also

- `concepts/events.md`
- `concepts/leases.md`
- `concepts/subscribe.md`
