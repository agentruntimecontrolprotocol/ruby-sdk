<h3 align="center">ARCP Ruby SDK</h3>

<p align="center"><strong>Ruby SDK for the Agent Runtime Control Protocol (ARCP) — submit, observe, and control long-running agent jobs from Ruby.</strong></p>

<p align="center">
  <a href="https://rubygems.org/gems/arcp"><img alt="gem" src="https://img.shields.io/gem/v/arcp.svg"></a>
  <a href="https://github.com/agentruntimecontrolprotocol/ruby-sdk/actions/workflows/test.yml"><img alt="CI" src="https://github.com/agentruntimecontrolprotocol/ruby-sdk/actions/workflows/test.yml/badge.svg"></a>
  <a href="https://codecov.io/gh/agentruntimecontrolprotocol/ruby-sdk"><img alt="codecov" src="https://codecov.io/gh/agentruntimecontrolprotocol/ruby-sdk/graph/badge.svg"></a>
  <a href="https://github.com/agentruntimecontrolprotocol/spec/blob/main/docs/draft-arcp-1.1.md"><img alt="ARCP" src="https://img.shields.io/badge/ARCP-v1.1%20draft-blue"></a>
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-Apache--2.0-lightgrey"></a>
  <a href="https://coderabbit.ai"><img alt="CodeRabbit" src="https://img.shields.io/coderabbit/prs/github/agentruntimecontrolprotocol/ruby-sdk?utm_source=oss&utm_medium=github&utm_campaign=agentruntimecontrolprotocol/ruby-sdk&labelColor=171717&color=FF570A&label=CodeRabbit+Reviews"></a>
</p>

<p align="center">
  <a href="https://github.com/agentruntimecontrolprotocol/spec/blob/main/docs/draft-arcp-1.1.md">Specification</a> ·
  <a href="#concepts">Concepts</a> ·
  <a href="#installation">Install</a> ·
  <a href="#quick-start">Quick start</a> ·
  <a href="docs/">Guides</a> ·
  <a href="docs/api/">API reference</a>
</p>

---

`arcp` is the Ruby reference implementation of [ARCP](https://github.com/agentruntimecontrolprotocol/spec/blob/main/docs/draft-arcp-1.1.md), the Agent Runtime Control Protocol. It covers both sides of the wire — `Arcp::Client` for submitting and observing jobs, `Arcp::Runtime::Runtime` for hosting agents — so either side can talk to any conformant peer in any language without hand-rolling the envelope, sequencing, or lease enforcement.

ARCP itself is a transport-agnostic wire protocol for long-running AI agent jobs. It owns the parts of agent infrastructure that don't change between products — sessions, durable event streams, capability leases, budgets, resume — and stays out of the parts that do. ARCP wraps the agent function; it does not define how agents are built, how tools are exposed (that's MCP), or how telemetry is exported (that's OpenTelemetry).

## Installation

Requires Ruby 3.3 or later. The gem runs on the `socketry/async` reactor and pulls in `async-websocket` for the default networked transport. The runtime currently buffers events in memory for replay; durable persistence is not shipped yet. Add it to a `Gemfile`:

```ruby
gem 'arcp', '~> 1.0'
```

```sh
bundle install
```

## Quick start

Connect to a runtime, submit a job, stream its events to completion:

```ruby
require 'async'
require 'arcp'

ECHO = lambda do |ctx|
  ctx.log(level: 'info', message: "echoing #{ctx.input.inspect}")
  ctx.progress(current: 1, total: 1, units: 'message')
  ctx.finish(result: { 'echoed' => ctx.input })
end

Sync do
  runtime = Arcp::Runtime::Runtime.new(
    auth_verifier: Arcp::Auth::Bearer.from_token('demo', principal_id: 'alice'),
    heartbeat_interval_sec: nil
  )
  runtime.register_agent(name: 'echo', versions: ['1.0.0'], default: '1.0.0', handler: ECHO)

  server_t, client_t = Arcp::Transport::MemoryTransport.pair
  server = Async { runtime.accept(server_t) }

  client = Arcp::Client.open(
    transport: client_t,
    auth: { 'scheme' => 'bearer', 'token' => 'demo' },
    client_name: 'quickstart'
  )

  handle = client.submit_job(agent: 'echo', input: { 'msg' => 'hi' })
  handle.subscribe(client: client).each { |event| puts "#{event.kind}: #{event.body.to_h}" }
  result = handle.get_result(client: client)
  puts "final: #{result.final_status} #{result.result.inspect}"

  client.close
  server.stop
end
```

This is the whole shape of the SDK: open a session, submit work, consume an ordered event stream, get a terminal result or error. Everything below is detail on those four moves.

## Concepts

ARCP organizes everything around four concerns — **identity**, **durability**, **authority**, and **observability** — expressed through five core objects:

- **Session** — a connection between a client and a runtime. A session carries identity (a bearer token), negotiates a feature set in a `hello`/`welcome` handshake, and keeps a replay window in the runtime's in-memory event log. Transparent reconnect resume is not wired through yet; use `history: true` and `from_event_seq` when you need to replay events. Jobs outlive the session that started them. See [§6](https://github.com/agentruntimecontrolprotocol/spec/blob/main/docs/draft-arcp-1.1.md).
- **Job** — one unit of agent work submitted into a session. A job has an identity, an optional idempotency key, a resolved agent version, and a lifecycle that ends in exactly one terminal state: `success`, `error`, `cancelled`, or `timed_out`. See [§7](https://github.com/agentruntimecontrolprotocol/spec/blob/main/docs/draft-arcp-1.1.md).
- **Event** — the ordered, session-scoped stream a job emits: logs, thoughts, tool calls and results, status, metrics, artifact references, progress, and streamed result chunks. Events carry strictly monotonic sequence numbers so the stream survives reconnects gap-free. See [§8](https://github.com/agentruntimecontrolprotocol/spec/blob/main/docs/draft-arcp-1.1.md).
- **Lease** — the authority a job runs under, expressed as capability grants (`fs.read`, `fs.write`, `net.fetch`, `tool.call`, `agent.delegate`, `cost.budget`, `model.use`). The runtime enforces the lease at every operation boundary; a job can never act outside it. Leases may carry a budget and an expiry, and may be subset and handed to sub-agents via delegation. See [§9](https://github.com/agentruntimecontrolprotocol/spec/blob/main/docs/draft-arcp-1.1.md).
- **Subscription** — read-only attachment to a job started elsewhere (e.g. a dashboard watching a job a CLI submitted). A subscriber observes the live event stream but cannot cancel or mutate the job. Distinct from *resume*, which continues the original session and carries cancel authority. See [§7.6](https://github.com/agentruntimecontrolprotocol/spec/blob/main/docs/draft-arcp-1.1.md).

The SDK models each of these as first-class objects; the rest of this README shows how.

## Guides

### Sessions and replay

Open a session, submit work, and replay buffered events from the retained log window when you need to recover missed history.

```ruby
require 'async'
require 'arcp'

Sync do
  client = Arcp::Client.open(
    transport: transport,
    auth: { 'scheme' => 'bearer', 'token' => ENV.fetch('ARCP_TOKEN') },
    client_name: 'resumable'
  )

  handle = client.submit_job(agent: 'long-runner')
  handle.subscribe(client: client).each do |event|
    puts "#{event.kind}: #{event.body.to_h}"
  end

  replay = client.subscribe_job(job_id: handle.job_id, from_event_seq: 0, history: true)
  replay.each do |event|
    puts "[replay] #{event.kind}"
  end
end
```

### Submitting jobs

Submit a job with an agent (optionally version-pinned as `name@version`), an input, and an optional lease request, idempotency key, and runtime limit.

```ruby
handle = client.submit_job(
  agent: 'weekly-report@2.1.0',
  input: { 'week' => '2026-W19' },
  lease_request: Arcp::Lease::LeaseRequest.new(
    capabilities: ['net.fetch'],
    expires_at: (Time.now.utc + 60).iso8601
  ),
  lease_constraints: Arcp::Lease::LeaseConstraints.new(
    expires_at: (Time.now.utc + 300).iso8601,
    max_budget: nil
  ),
  idempotency_key: 'weekly-report-2026-W19',
  max_runtime_sec: 300
)

puts "job_id           = #{handle.job_id}"
puts "resolved agent   = #{handle.agent.inspect}"
puts "effective lease  = #{handle.lease&.to_h.inspect}"
```

### Consuming events

Iterate the ordered event stream — `log`, `thought`, `tool_call`, `tool_result`, `status`, `metric`, `artifact_ref`, `progress`, `result_chunk` — and optionally acknowledge progress so the runtime can release buffered events early.

```ruby
last_seq = 0
handle.subscribe(client: client).each do |event|
  case event.kind
  when Arcp::Job::EventKind::LOG
    puts event.body.message
  when Arcp::Job::EventKind::TOOL_CALL
    puts "-> tool #{event.body.name}(#{event.body.arguments.inspect})"
  when Arcp::Job::EventKind::METRIC
    puts "metric #{event.body.name}=#{event.body.value}#{event.body.unit}"
  when Arcp::Job::EventKind::PROGRESS
    puts "progress #{event.body.current}/#{event.body.total} #{event.body.units}"
  end
  last_seq += 1
  client.ack(last_seq) if (last_seq % 32).zero?  # coalesced session.ack
end
```

### Leases and budgets

Request capabilities, a budget, and an expiry; read budget-remaining metrics as they arrive; handle the runtime's enforcement decisions.

```ruby
handle = client.submit_job(
  agent: 'web-research',
  input: { 'iterations' => 8 },
  lease_request: Arcp::Lease::LeaseRequest.new(
    capabilities: ['tool.call', 'cost.spend'],
    budget: Arcp::Lease::CostBudget.parse(['USD:1.00']),
    expires_at: (Time.now.utc + 600).iso8601
  )
)

puts "initial budget = #{handle.lease&.budget&.to_a.inspect}"

handle.subscribe(client: client).each do |event|
  next unless event.kind == Arcp::Job::EventKind::METRIC
  next unless event.body.name == 'cost.budget.remaining'

  puts "budget remaining: #{event.body.value} #{event.body.unit}"
end

begin
  handle.get_result(client: client)
rescue Arcp::Errors::BudgetExhausted, Arcp::Errors::LeaseExpired => e
  # Never retryable — resubmit with a fresh lease/budget instead.
  warn "job ended: #{e.code} #{e.message}"
end
```

### Subscribing to jobs

Attach read-only to a job submitted elsewhere and observe its live stream (with optional history replay) without cancel authority.

```ruby
Sync do
  observer = Arcp::Client.open(
    transport: dashboard_transport,
    auth: { 'scheme' => 'bearer', 'token' => ENV.fetch('ARCP_TOKEN') },
    client_name: 'dashboard'
  )

  running = observer.list_jobs(status: 'running', limit: 1).first
  stream  = observer.subscribe_job(job_id: running.job_id, from_event_seq: 0, history: true)

  stream.each do |event|
    puts "[#{running.job_id}] #{event.kind}"
  end

  observer.close
end
```

### Error handling

Catch the typed error taxonomy and respect the `retryable` flag — `LEASE_EXPIRED` and `BUDGET_EXHAUSTED` are never retryable; a naive retry fails identically.

```ruby
begin
  handle = client.submit_job(agent: 'flaky', input: {})
  handle.get_result(client: client)
rescue Arcp::Errors::LeaseExpired, Arcp::Errors::BudgetExhausted => e
  raise e  # resubmit with a fresh lease / budget instead
rescue Arcp::Error => e
  if e.retryable?
    # safe to retry with backoff (e.g. INTERNAL_ERROR, RATE_LIMITED, TIMEOUT)
    retry_with_backoff(e)
  else
    raise
  end
end
```

## Feature support

ARCP features this SDK negotiates during the `hello`/`welcome` handshake:

| Feature flag | Status |
|---|---|
| `heartbeat` | Supported |
| `ack` | Supported |
| `list_jobs` | Supported |
| `subscribe` | Supported |
| `lease_expires_at` | Supported |
| `cost.budget` | Supported |
| `model.use` | Supported |
| `provisioned_credentials` | Supported |
| `progress` | Supported |
| `result_chunk` | Supported |
| `agent_versions` | Supported |

## Transport

ARCP is transport-agnostic. This SDK ships a WebSocket transport (default), a stdio transport for in-process child runtimes, and an in-memory transport for tests. WebSocket is the default for networked runtimes; stdio is used for in-process child runtimes. Select one by constructing the corresponding transport object and passing it to `Arcp::Client.open(transport:, ...)`: `Arcp::Transport::WebSocketTransport.new(connection: ws)` for production (wrap an open `Async::WebSocket::Connection`, typically hosted under `falcon`), `Arcp::Transport::StdioTransport` for co-process agents, or `Arcp::Transport::MemoryTransport.pair` for in-process tests and embedded clients.

## API reference

Full API reference — every type, method, and event payload — is in [`docs/`](docs/) (YARD-generated reference under [`docs/api/`](docs/api/), rebuilt with `bundle exec rake docs`).

## Versioning and compatibility

This SDK speaks **ARCP v1.1 (draft)**. The SDK follows semantic versioning independently of the protocol; the negotiated runtime version is available on `client.session.runtime_version`. A runtime advertising a different ARCP MAJOR is not guaranteed compatible. Feature mismatches degrade gracefully: the effective feature set is the intersection of what the client and runtime advertise, and the SDK will not use a feature outside it.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). Protocol questions and proposed changes belong in the [spec repository](https://github.com/agentruntimecontrolprotocol/spec); SDK bugs and feature requests belong here.

## License

Apache-2.0 — see [`LICENSE`](LICENSE).
