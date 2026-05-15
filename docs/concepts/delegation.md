---
title: Delegation
sdk: ruby
kind: concept
order: 16
spec_sections: [§10, §9.4]
---

# Delegation

## What

A handler can spawn child work by emitting a `delegate` event carrying a
child job_id, agent reference, and a child lease. The child lease MUST
be a strict subset of the parent's lease.

## Delegate event

```ruby
parent_lease = $arcp_runtime.lease_manager.get(ctx.job_id)
child_request = Arcp::Lease::LeaseRequest.new(
  capabilities: ['compute.read'],
  budget: Arcp::Lease::CostBudget.parse(['USD:1.00']),
  expires_at: nil
)
child_lease = Arcp::Lease::Subsetting.bound(
  parent: parent_lease,
  request: child_request
)

ctx.emit(
  kind: Arcp::Job::EventKind::DELEGATE,
  body: Arcp::Job::EventBody::Delegate.new(
    child_job_id: "child_#{ctx.job_id}",
    agent: 'child',
    lease: child_lease
  )
)
```

## Subset rules

`Arcp::Lease::Subsetting.bound` enforces three rules:

- `request.capabilities` MUST be a subset of `parent.capabilities`
- `request.expires_at` (if set) MUST be `<= parent.expires_at`
- `request.budget` (if set) MUST be `<=` parent's remaining per currency

Any violation raises `Arcp::Errors::LeaseSubsetViolation`.

## See also

- `concepts/leases.md`
- `guides/budgets.md`
