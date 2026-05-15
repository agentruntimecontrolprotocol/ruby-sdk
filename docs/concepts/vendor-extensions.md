---
title: Vendor extensions
sdk: ruby
kind: concept
order: 19
spec_sections: [§5.1, §8.2, §15]
---

# Vendor extensions

## What

Event kinds prefixed `x-vendor.` carry implementation-specific data. The
runtime forwards them verbatim; clients that don't recognize the prefix
ignore them.

## Namespace conventions

- `x-vendor.<org>.<event>` — owned by `<org>`
- Bodies are arbitrary JSON-serializable Hashes
- Standard kinds (without the `x-vendor.` prefix) are reserved

## Emit from a handler

```ruby
ctx.emit(
  kind: 'x-vendor.acme.progress',
  body: { 'stage' => 'mapping', 'percent' => 50 }
)
```

## Receive on a client

Unknown kinds round-trip through `Arcp::Job::Event` with a frozen `Hash`
body — no `EventBody` class is allocated.

```ruby
handle.subscribe(client: client).each do |event|
  if event.kind.start_with?('x-vendor.acme.')
    stage = event.body['stage']
    pct = event.body['percent']
    # ...
  end
end
```

`event.known?` returns `false` for vendor kinds.

## See also

- `concepts/events.md`
