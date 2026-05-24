---
title: Leases
sdk: ruby
kind: guide
order: 22
spec_sections: [§9]
---

# Leases

A lease is the runtime's grant of authority to a job: a set of
capabilities, an optional expiry, optional model patterns, and an
optional per-currency budget. The runtime issues one on `job.accepted`
and attaches it to the job context. Delegation requires the child lease
to be a strict subset.

## Capabilities

Capabilities are opaque strings: `compute.read`, `net.http`,
`cost.spend`, etc. The runtime decides what each means; the SDK only
enforces subset relations at delegate time.

## expires_at

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

`Arcp::Runtime::LeaseManager#try_spend!` atomically decrements the
bound counter via `BudgetCounter#try_decrement`; overspend raises
`Arcp::Errors::BudgetExhausted`. See `guides/jobs.md` for the full
spend workflow.

## model.use

```ruby
lease_request = Arcp::Lease::LeaseRequest.new(
  capabilities: ['cost.spend'],
  model_use:    ['tier-fast/*']
)
```

`model.use` is a set of glob patterns for model ids. Runtime code in
the path of an LLM call can enforce it with:

```ruby
$arcp_runtime.lease_manager.check_model!(
  ctx.job_id,
  model_id: 'tier-fast/gpt-4o-mini'
)
```

A miss raises `Arcp::Errors::PermissionDenied`. Delegate subsetting
also checks `model.use`; a child may keep the same pattern or narrow a
parent glob to a literal model id.

## Subsetting on delegate

```ruby
parent = $arcp_runtime.lease_manager.get(ctx.job_id)
child_request = Arcp::Lease::LeaseRequest.new(
  capabilities: ['compute.read'],
  budget:       Arcp::Lease::CostBudget.parse(['USD:0.25']),
  model_use:    ['tier-fast/gpt-4o-mini'],
  expires_at:   nil
)
child = Arcp::Lease::Subsetting.bound(parent: parent, request: child_request)
```

Excess capability, `expires_at` beyond parent, or per-currency budget
above parent's remaining all raise `Arcp::Errors::LeaseSubsetViolation`.

## See also

- `guides/delegation.md`
- `guides/jobs.md`
- `guides/credentials.md`
