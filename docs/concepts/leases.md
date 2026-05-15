---
title: Leases
sdk: ruby
kind: concept
order: 12
spec_sections: [§9]
---

# Leases

## What

A lease is the runtime's grant of authority to a job: a set of
capabilities, an optional expiry, and an optional per-currency budget.
The runtime issues one on `job.accepted` and attaches it to the job
context. Delegation requires the child lease to be a strict subset.

## Capabilities

Capabilities are opaque strings: `compute.read`, `net.http`,
`cost.spend`, etc. The runtime decides what each means; the SDK only
enforces subset relations at delegate time.

## Expires_at

```ruby
handle = client.submit_job(
  agent: 'reporter',
  lease_constraints: Arcp::Lease::LeaseConstraints.new(
    expires_at: '2026-05-14T12:00:00Z',  # MUST be UTC 'Z'
    max_budget: nil
  )
)
```

The runtime issues a lease with `expires_at` no later than the
constraint. After expiry, attempts to use the lease raise
`Arcp::Errors::LeaseExpired`.

## cost.budget

```ruby
budget = Arcp::Lease::CostBudget.parse(['USD:1.00', 'EUR:0.50'])
budget.remaining('USD') # => BigDecimal('1.00')
```

`BudgetCounter#try_spend!` atomically decrements; overspend raises
`Arcp::Errors::BudgetExhausted`.

## Subsetting on delegate

```ruby
parent = $arcp_runtime.lease_manager.get(ctx.job_id)
child_request = Arcp::Lease::LeaseRequest.new(
  capabilities: ['compute.read'],
  budget: Arcp::Lease::CostBudget.parse(['USD:0.25']),
  expires_at: nil
)
child = Arcp::Lease::Subsetting.bound(parent: parent, request: child_request)
```

Excess capability, expires_at beyond parent, or per-currency budget
above parent's remaining all raise `Arcp::Errors::LeaseSubsetViolation`.

## See also

- `concepts/delegation.md`
- `guides/budgets.md`
