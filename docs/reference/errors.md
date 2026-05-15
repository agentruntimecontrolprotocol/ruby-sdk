---
title: Errors
sdk: ruby
kind: reference
order: 50
spec_sections: [§12]
---

# Errors

15 wire codes, each mapped to a class under `Arcp::Errors`. Plus three
library-internal codes never sent on the wire.

## Wire codes

| Code | Class | retryable? default |
| --- | --- | --- |
| CANCELLED | `Arcp::Errors::Cancelled` | no |
| INVALID_REQUEST | `Arcp::Errors::InvalidRequest` | no |
| UNAUTHENTICATED | `Arcp::Errors::Unauthenticated` | no |
| PERMISSION_DENIED | `Arcp::Errors::PermissionDenied` | no |
| JOB_NOT_FOUND | `Arcp::Errors::JobNotFound` | no |
| AGENT_NOT_AVAILABLE | `Arcp::Errors::AgentNotAvailable` | yes |
| DUPLICATE_KEY | `Arcp::Errors::DuplicateKey` | no |
| RATE_LIMITED | `Arcp::Errors::RateLimited` | yes |
| INTERNAL_ERROR | `Arcp::Errors::Internal` | yes |
| HEARTBEAT_LOST | `Arcp::Errors::HeartbeatLost` | yes |
| BACKPRESSURE | `Arcp::Errors::Backpressure` | yes |
| PROTOCOL_VIOLATION | `Arcp::Errors::ProtocolViolation` | no |
| TIMEOUT | `Arcp::Errors::Timeout` | yes |
| RESUME_WINDOW_EXPIRED | `Arcp::Errors::ResumeWindowExpired` | no |
| LEASE_SUBSET_VIOLATION | `Arcp::Errors::LeaseSubsetViolation` | no |
| AGENT_VERSION_NOT_AVAILABLE | `Arcp::Errors::AgentVersionNotAvailable` | no |
| LEASE_EXPIRED | `Arcp::Errors::LeaseExpired` | no |
| BUDGET_EXHAUSTED | `Arcp::Errors::BudgetExhausted` | no |

(Table has 18 rows; the spec text in §12 specifies 15 wire codes plus
the three subsetting/lease/budget codes added for v1.)

## Library-internal codes

| Code | Class | Notes |
| --- | --- | --- |
| UNNEGOTIATED_FEATURE | `Arcp::Errors::UnnegotiatedFeature` | Client tried to call a feature not in the negotiated set. |
| INTERNAL_ERROR | `Arcp::Error` (base) | Abstract base; not sent on the wire by itself. |
| INTERNAL_ERROR | fallback for unknown codes | `Arcp::Errors.for(unknown_code)` returns `Internal`. |

## Inspecting an error

```ruby
begin
  client.submit_job(agent: 'nope')
rescue Arcp::Error => e
  e.code        # 'AGENT_NOT_AVAILABLE'
  e.message     # human string
  e.retryable?  # true | false
  e.details     # Hash, frozen
end
```

## Building from a wire payload

```ruby
err = Arcp::Errors.for('LEASE_EXPIRED', message: 'lease expired', details: { 'lease_id' => 'lse_...' })
raise err
```

## Lists

```ruby
Arcp::Errors::WIRE_CODES            # all 15+3 wire codes
Arcp::Errors::RETRYABLE_BY_DEFAULT  # codes where retryable? defaults to true
```
