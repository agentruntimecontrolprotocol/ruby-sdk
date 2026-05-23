# Recipes

Composed ARCP features wired around a real LLM workload. Unlike the
single-feature [`samples/`](../samples/) — which use toy agents (echo,
slow timer, fake budget) — each recipe is a complete end-to-end shape
with an actual provider SDK driving the agent.

Each subdirectory mirrors the samples layout:

| File        | Purpose                                                      |
| ----------- | ------------------------------------------------------------ |
| `server.rb` | Agent handler + runtime registration                         |
| `client.rb` | Submits the job, observes events, returns the terminal state |
| `run.rb`    | Wires both sides with `MemoryTransport.pair` under `Sync { }` |

## Running

```
bundle exec ruby recipes/<name>/run.rb
```

Provider gems (`anthropic`, `ruby-openai`) are not pinned in the
gemspec because they are not core dependencies — install whichever
ones the recipe you want to run needs:

```
gem install anthropic ruby-openai
```

## [multi_agent_budget/](multi_agent_budget/) — OpenAI

The planner decomposes a question into sub-questions and delegates each
to a worker carrying a budget slice carved from its own remaining cap.
After each grant the planner emits a `cost.delegate` metric on itself
so the runtime's subset check at the next delegate sees an honest
remaining balance. Workers that overspend trip `BudgetExhausted`;
sub-questions that no longer fit are skipped before the delegate.

## [email_vendor_leases/](email_vendor_leases/) — Claude

A triage agent runs Claude through a tool-use loop with three tools, but
the lease grants only the two read-only ones. When the model proposes
`send_reply` the `LeaseManager#check!` raises `PermissionDenied` and
the agent feeds the denial back to Claude, which observes the deny and
returns a drafted-but-unsent reply. Each `inbox_read` also emits an
`x-vendor.acme.email.parsed` event so dashboards recognising the
namespace can render parsed metadata specially.

## [stream_resume/](stream_resume/) — GLM-5

The writer pipes GLM-5's streaming deltas into `ctx.stream_result`,
batching ~200 chars per `result_chunk` envelope. Every envelope lands
in the runtime's `EventLog` under a monotonic `event_seq`. The client
drops the transport mid-stream, opens a fresh session with
`Client.resume`, and the runtime replays every envelope past the
cutoff so reassembly completes seamlessly across the gap.

## [mcp_skill/](mcp_skill/) — MCP bridge

A minimal MCP server fronts the [multi_agent_budget](multi_agent_budget/)
planner so any MCP host (Claude Code, Cursor, Desktop) can call it as
a single `research` tool. The bridge keeps one long-lived ARCP session;
each MCP tool invocation submits a fresh planner job and returns the
terminal result as the tool's text response. A Claude Code skill at
[skills/research/SKILL.md](mcp_skill/skills/research/SKILL.md) tells
the model when to reach for the tool.
