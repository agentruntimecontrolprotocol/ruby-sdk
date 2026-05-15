---
title: Budgets
sdk: ruby
kind: guide
order: 21
spec_sections: [§9.6, §12]
---

# Budgets

The `cost.budget` capability caps spend per currency. Amounts are
`BigDecimal` end-to-end — no float drift on the wire or in the
counter.

## Request a budget at submit

```ruby
handle = client.submit_job(
  agent: 'shopper',
  lease_request: Arcp::Lease::LeaseRequest.new(
    capabilities: ['cost.spend'],
    budget: Arcp::Lease::CostBudget.parse(['USD:1.00']),
    expires_at: nil
  )
)
```

The wire form is a list of `currency:amount` strings (`['USD:1.00']`).
`CostBudget.parse` round-trips through `BigDecimal` and back via
`#to_a`.

## Spend from a handler

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

## Client-side exhaustion

```ruby
begin
  handle.get_result(client: client)
rescue Arcp::Errors::BudgetExhausted => e
  e.details # { 'currency' => 'USD', 'requested' => ..., 'remaining' => ... }
end
```

## Inspect remaining

```ruby
counter = $arcp_runtime.lease_manager.counter(job_id)
counter.remaining # { 'USD' => BigDecimal('0.30') }
counter.get('USD') # => BigDecimal('0.30')
```
