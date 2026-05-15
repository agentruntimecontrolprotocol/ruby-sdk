---
title: Agent versioning
sdk: ruby
kind: guide
order: 20
spec_sections: [§7.5, §12]
---

# Agent versioning

Agents declare a fixed set of versions and one default. Clients submit
either by name (defaults) or by `name@version` (pin).

## Register multiple versions

```ruby
handler = ->(ctx) { ctx.finish(result: ctx.agent) }

runtime.register_agent(
  name: 'code-refactor',
  versions: %w[1.0.0 2.0.0],
  default: '2.0.0',
  handler: handler
)
```

The same handler serves both versions; the handler reads `ctx.agent` to
discover which `name@version` ref the runtime resolved.

## Submit with defaults

```ruby
client.submit_job(agent: 'code-refactor')
# resolves to 'code-refactor@2.0.0'
```

## Submit pinned

```ruby
client.submit_job(agent: 'code-refactor@1.0.0')
# runs the 1.0.0 path
```

## Unknown version

```ruby
begin
  client.submit_job(agent: 'code-refactor@9.9.9')
rescue Arcp::Errors::AgentVersionNotAvailable => e
  e.details['available_versions'] # => ['1.0.0', '2.0.0']
end
```

`Arcp::Errors::AgentVersionNotAvailable` carries the available versions
in `details` for fallback logic.

## Resolution helper

`Arcp::Session::AgentInventory#resolve(ref)` returns the canonical
`name@version` string or `nil`. Use it client-side to validate a ref
before submit:

```ruby
client.session.capabilities.agents.resolve('code-refactor@1.0.0')
# => 'code-refactor@1.0.0'
client.session.capabilities.agents.resolve('code-refactor@9.9.9')
# => nil
```
