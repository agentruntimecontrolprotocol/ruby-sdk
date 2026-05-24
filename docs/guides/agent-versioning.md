---
title: Agent versioning
sdk: ruby
kind: guide
order: 13
spec_sections: [§7.5]
---

# Agent versioning

Agents are registered under a stable name and an optional set of
published versions. When a client submits `name@version`, the runtime
resolves that exact version if it exists; when the client submits only
`name`, the runtime uses the registered default.

## Register versions

```ruby
runtime.register_agent(
  name: 'code-refactor',
  versions: %w[1.0.0 2.0.0],
  default: '2.0.0',
  handler: ->(ctx) { ctx.finish(result: ctx.agent) }
)
```

## Submit a version-pinned job

```ruby
handle = client.submit_job(agent: 'code-refactor@1.0.0')
result = handle.get_result(client: client)
```

## Validate a ref first

`Arcp::Session::AgentInventory#resolve(ref)` returns the normalized
`name@version` string or `nil` if the ref is unknown. On failure, the
runtime raises `Arcp::Errors::AgentVersionNotAvailable` with
`details['available']` populated with the registered versions.

```ruby
inventory = client.session.capabilities.agents
inventory.resolve('code-refactor@1.0.0') # => "code-refactor@1.0.0"
inventory.resolve('code-refactor@9.9.9') # => nil
```

## See also

- `guides/sessions.md`
- `guides/jobs.md`
