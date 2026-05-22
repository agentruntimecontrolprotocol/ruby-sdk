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

## Lease-scoped vendor credentials (email-vendor-leases)

Provision a short-lived upstream key that is automatically revoked when the
job ends. The runtime copies `cost.budget`, `model.use`, and `expires_at`
into the credential's constraints so the upstream gateway can enforce the
same bounds.

```ruby
# 1. Configure a provisioner at runtime build time
provisioner = Arcp::Credentials::InMemoryProvisioner.new(
  endpoint: 'https://mail-gateway.example/v1',
  profile:  'sendgrid'
)

runtime = Arcp::Runtime::Runtime.new(
  auth_verifier:       auth,
  credential_provisioner: provisioner,
  credential_store:    Arcp::Credentials::InMemoryStore.new
)

# 2. Submit a job requesting the spend capability
handle = client.submit_job(
  agent: 'email-sender',
  lease_request: Arcp::Lease::LeaseRequest.new(
    capabilities: ['cost.spend'],
    budget:       Arcp::Lease::CostBudget.parse(['USD:0.10']),
    expires_at:   (Time.now.utc + 300).strftime('%FT%TZ')
  )
)

# 3. Retrieve the provisioned credential from the accepted handle
credential = handle.credential_for(
  endpoint: 'https://mail-gateway.example/v1'
)

# credential.value holds the short-lived key; never log it directly
# Use credential.to_redacted_h for logs/metrics
puts credential.to_redacted_h.inspect

handle.get_result(client: client)
# Credential is revoked automatically on job termination
```

## MCP-style skill wrapper (mcp-skill)

Wrap a single-operation agent so it looks like an MCP tool call: one input
hash in, one structured result out, all errors mapped to ARCP error codes.

```ruby
module Skills
  module SummarizeText
    # @param text [String]
    # @return [Hash]
    def self.call(client:, text:)
      handle = client.submit_job(
        agent: 'summarizer@1',
        input: { 'text' => text }
      )

      result = handle.get_result(client: client)
      result.output
    rescue Arcp::Errors::LeaseExpired, Arcp::Errors::BudgetExhausted => e
      { 'error' => e.code, 'message' => e.message }
    rescue Arcp::Errors::Error => e
      { 'error' => e.code, 'message' => e.message, 'retryable' => e.retryable? }
    end
  end
end

# Caller
Sync do
  Arcp::Client.connect(transport: transport) do |client|
    puts Skills::SummarizeText.call(
      client: client,
      text:   'Long article text here...'
    ).inspect
  end
end
```

## Multi-agent budget (multi-agent-budget)

Delegate a child job with a sub-budget carved from the parent lease. The
parent's `cost.budget` decrements as the child spends; `LeaseSubsetViolation`
is raised if the requested child budget exceeds the parent's remaining amount.

```ruby
# Server-side handler for the orchestrator agent
orchestrator = Arcp::Runtime::Handler.new('orchestrator') do |ctx|
  parent_lease = ctx.lease

  # Carve a sub-budget for the child job
  child_request = Arcp::Lease::LeaseRequest.new(
    capabilities: parent_lease.capabilities & ['cost.spend'],
    budget:       Arcp::Lease::CostBudget.parse(['USD:0.25']),
    expires_at:   parent_lease.expires_at
  )
  child_lease = Arcp::Lease::Subsetting.bound(
    parent:  parent_lease,
    request: child_request
  )

  # Emit a delegate event so the runtime issues a child job
  ctx.emit(:delegate,
    agent:       'sub-worker',
    lease:       child_lease,
    input:       { 'task' => 'unit-of-work' },
    delegate_id: SecureRandom.hex(8))

  # Wait for all delegate events to settle, then finish
  ctx.finish(output: { 'status' => 'done' })
end

# Client-side — request the parent budget
handle = client.submit_job(
  agent: 'orchestrator',
  lease_request: Arcp::Lease::LeaseRequest.new(
    capabilities: ['cost.spend'],
    budget:       Arcp::Lease::CostBudget.parse(['USD:1.00'])
  )
)

handle.subscribe(client: client).each do |event|
  if event.kind == Arcp::Job::EventKind::DELEGATE
    puts "Delegated to #{event.body.agent} " \
         "with budget #{event.body.lease.budget.inspect}"
  end
end

result = handle.get_result(client: client)
puts result.output.inspect
```

## Stream + resume (stream-resume)

Assemble a chunked result across a simulated transport drop. The client
reconnects with the saved `resume_token` and `last_event_seq`, and the
runtime replays missed chunks from its event log.

```ruby
resume_token  = nil
last_seq      = 0
assembled     = []

# First connection — collect some chunks then simulate a drop
Arcp::Client.connect(transport: first_transport) do |client|
  handle = client.submit_job(agent: 'big-streamer')

  handle.subscribe(client: client).each do |event|
    case event.kind
    when Arcp::Job::EventKind::RESULT_CHUNK
      assembled << event.body.decoded
      last_seq = event.seq

    when Arcp::Job::EventKind::STATUS
      if event.body.phase == 'connected'
        # Stash the resume token from the welcome payload
        resume_token = client.session.resume_token
        break  # simulate drop after first few chunks
      end
    end
  end
end

# Second connection — resume from where we left off
second_transport = build_transport(
  resume_token:  resume_token,
  last_event_seq: last_seq
)

Arcp::Client.connect(transport: second_transport) do |client|
  handle = client.reattach_job(handle.job_id)

  handle.subscribe(client: client).each do |event|
    next unless event.kind == Arcp::Job::EventKind::RESULT_CHUNK

    assembled << event.body.decoded
    break unless event.body.more
  end

  handle.get_result(client: client)
end

full_text = assembled.join
puts "Assembled #{full_text.bytesize} bytes across reconnect"
```
