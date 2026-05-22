---
title: Provisioned credentials
sdk: ruby
kind: guide
order: 22
spec_sections: [§9.7, §9.8]
---

# Provisioned credentials

Provisioned credentials let a runtime mint short-lived upstream keys for a
job after the lease is finalized. The key is returned only on
`job.accepted`, scoped by the lease, and revoked when the job terminates.

## Configure the runtime

```ruby
provisioner = Arcp::Credentials::InMemoryProvisioner.new(
  endpoint: 'https://llm-gateway.example/v1',
  profile: 'openai'
)

runtime = Arcp::Runtime::Runtime.new(
  auth_verifier: auth,
  credential_provisioner: provisioner,
  credential_store: Arcp::Credentials::InMemoryStore.new
)
```

When a provisioner is configured, the runtime advertises the
`model.use` and `provisioned_credentials` features during capability
negotiation. Without a provisioner, both features are omitted.

## Request model access

```ruby
handle = client.submit_job(
  agent: 'gateway-caller',
  lease_request: Arcp::Lease::LeaseRequest.new(
    capabilities: ['cost.spend'],
    budget: Arcp::Lease::CostBudget.parse(['USD:1.00']),
    model_use: ['tier-fast/*']
  )
)

credential = handle.credential_for(endpoint: 'https://llm-gateway.example/v1')
```

The runtime copies `cost.budget`, `model.use`, and `expires_at` into the
credential constraints so an upstream gateway can enforce the same bounds.

## Implement a provisioner

```ruby
class LiteLLMProvisioner
  include Arcp::CredentialProvisioner

  def issue(lease:, job_id:, agent:, principal_id:)
    response = generate_litellm_key(
      budget: lease.budget&.to_a,
      models: lease.model_use,
      expires_at: lease.expires_at
    )

    [
      Arcp::Credential.new(
        id: response.fetch('key_alias'),
        scheme: Arcp::Credential::SCHEME_BEARER,
        value: response.fetch('key'),
        endpoint: 'https://llm-gateway.example/v1',
        profile: 'openai',
        constraints: {
          'cost.budget' => lease.budget&.to_a,
          'model.use' => lease.model_use,
          'expires_at' => lease.expires_at
        }.compact
      )
    ]
  end

  def revoke(credential_id:)
    delete_litellm_key(credential_id)
  end
end
```

Vendor-specific HTTP clients should live outside the core gem. The SDK only
defines the interface and value objects.

When an upstream gateway reports budget exhaustion, map it back to the ARCP
error boundary:

```ruby
begin
  call_gateway(credential)
rescue StandardError => e
  raise Arcp::Credentials.translate_upstream_error(e)
end
```

## Rotation and revocation

Agents can rotate a credential value mid-job:

```ruby
ctx.rotate_credential(id: 'cred_job_123_0', new_value: 'sk-new-value')
```

That emits a `status` event with `phase: 'credential_rotated'` and a
`fields` hash containing the new `{ id, value }`. Treat this event as
secret-bearing data.

The runtime revokes outstanding credential ids on success, error,
cancellation, and timeout. `CredentialRegistry` retries transient revoke
failures once and keeps any failed id in the configured store for later
reconciliation.

## Security notes

`Credential#to_h` is the wire representation and includes `value`.
Use `Credential#to_redacted_h` for logs, metrics, and examples.
`session.list_jobs` summaries never include credentials.
