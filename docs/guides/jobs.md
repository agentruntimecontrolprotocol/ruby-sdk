---
title: Jobs
sdk: ruby
kind: guide
order: 20
spec_sections: [§7, §9.6, §12]
---

# Jobs

A job is one invocation of one agent within an open session. It has a
deterministic lifecycle: `job.submit` → `job.accepted` → stream of
`job.event` → terminal `job.result` or `job.error`.

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
  agent:           'echo',
  input:           { 'msg' => 'hi' },
  idempotency_key: 'req-42',
  max_runtime_sec: 60
)
handle.job_id        # String
handle.lease         # Arcp::Lease::Lease (issued by runtime)
handle.submitted_at  # ISO-8601 UTC

handle.subscribe(client: client).each { |ev| puts ev.kind }
result = handle.get_result(client: client)
result.final_status  # 'success'
result.result        # whatever the handler passed to ctx.finish(result:)
```

## Idempotency

Submitting twice with the same `idempotency_key` resolves to the same
`job_id`. A different payload under an existing key raises
`Arcp::Errors::DuplicateKey`.

## Cancellation

```ruby
handle.cancel(client: client, reason: 'user requested stop')
begin
  handle.get_result(client: client)
rescue Arcp::Errors::Cancelled
  # expected terminal state
end
```

## Listing jobs

```ruby
client.list_jobs(status: 'succeeded', limit: 25).each do |summary|
  puts summary.job_id
end
```

Returns a lazy `Enumerator` that walks `next_cursor` automatically.

## Cost budgets

The `cost.budget` capability caps spend per currency. Amounts are
`BigDecimal` end-to-end — no float drift on the wire or in the counter.

### Request a budget at submit

```ruby
handle = client.submit_job(
  agent: 'shopper',
  lease_request: Arcp::Lease::LeaseRequest.new(
    capabilities: ['cost.spend'],
    budget:       Arcp::Lease::CostBudget.parse(['USD:1.00']),
    expires_at:   nil
  )
)
```

The wire form is a list of `currency:amount` strings (`['USD:1.00']`).
`CostBudget.parse` round-trips through `BigDecimal` and back via `#to_a`.

### Spend from a handler

```ruby
HANDLER = lambda do |ctx|
  lm = $arcp_runtime.lease_manager
  [BigDecimal('0.42'), BigDecimal('0.70')].each do |amount|
    ctx.metric(name: 'cost.search', value: amount.to_s('F'), unit: 'USD')
    lm.try_spend!(ctx.job_id, 'USD', amount)
  end
  ctx.finish(result: 'spent')
end
```

`try_spend!` atomically decrements the lease's `BudgetCounter`. If the
balance goes negative, the runtime emits `job.error` with code
`BUDGET_EXHAUSTED`.

When spend is enforced by an upstream gateway instead of local counters,
configure provisioned credentials so `cost.budget` is baked into the
issued key — see `guides/credentials.md`.

### Client-side exhaustion

```ruby
begin
  handle.get_result(client: client)
rescue Arcp::Errors::BudgetExhausted => e
  e.details # { 'currency' => 'USD', 'requested' => ..., 'remaining' => ... }
end
```

### Inspect remaining balance

```ruby
counter = $arcp_runtime.lease_manager.counter(job_id)
counter.remaining # { 'USD' => BigDecimal('0.30') }
counter.get('USD') # => BigDecimal('0.30')
```

## See also

- `guides/job-events.md`
- `guides/leases.md`
- `guides/delegation.md`
