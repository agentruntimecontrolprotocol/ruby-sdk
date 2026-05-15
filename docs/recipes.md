---
title: Recipes
sdk: ruby
kind: guide
order: 80
spec_sections: [§7, §8, §9]
---

# Recipes

Each recipe assumes a `client` (an `Arcp::Client`) is in scope, opened
under a `Sync { }` block.

## Submit a job

```ruby
handle = client.submit_job(agent: 'echo', input: { 'msg' => 'hi' })
```

## Stream events

```ruby
handle.subscribe(client: client).each do |event|
  case event.kind
  when Arcp::Job::EventKind::PROGRESS
    puts "#{event.body.current}/#{event.body.total}"
  when Arcp::Job::EventKind::LOG
    puts event.body.message
  end
end
```

## Cancel mid-flight

```ruby
handle = client.submit_job(agent: 'sleepy')
Async::Task.current.sleep(0.05)
handle.cancel(client: client, reason: 'user requested stop')
begin
  handle.get_result(client: client)
rescue Arcp::Errors::Cancelled
  # expected
end
```

## list_jobs with pagination

```ruby
client.list_jobs(status: 'succeeded', limit: 25).each do |summary|
  puts summary.job_id
end
```

The returned `Enumerator` is lazy and walks `next_cursor` for you.

## Cost budgets

```ruby
handle = client.submit_job(
  agent: 'shopper',
  lease_request: Arcp::Lease::LeaseRequest.new(
    capabilities: ['cost.spend'],
    budget: Arcp::Lease::CostBudget.parse(['USD:1.00']),
    expires_at: nil
  )
)
begin
  handle.subscribe(client: client).to_a
  handle.get_result(client: client)
rescue Arcp::Errors::BudgetExhausted => e
  puts e.details
end
```

## Assemble a streamed result

```ruby
handle = client.submit_job(agent: 'streamer')
chunks = handle.subscribe(client: client).select do |ev|
  ev.kind == Arcp::Job::EventKind::RESULT_CHUNK
end
assembled = chunks.map { |ev| ev.body.decoded }.join
result = handle.get_result(client: client)
# result.result_id matches the first chunk's result_id
```

## Pin an agent version

```ruby
client.submit_job(agent: 'code-refactor@1.0.0', input: { ... })
```

Omit `@version` to use the registered default.
