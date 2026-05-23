---
name: research
description: Decompose a complex question into sub-questions and research each under a shared budget cap. Use when the user asks an open-ended research-style question and wants structured, decomposed analysis rather than a single direct answer.
---

# Research skill

This skill is backed by the `arcp-research-bridge` MCP server, which
fronts an ARCP multi-agent runtime: one planner decomposes the user's
question into sub-questions and delegates each to a worker child. All
work runs under a single cost cap that cascades across the delegation
tree.

## When to use

- The user asks an open-ended research question ("What are the major
  causes of X?", "How does Y compare to Z?", "Survey the landscape of ...").
- The user explicitly wants structured / decomposed analysis with
  per-sub-question findings rather than one paragraph.
- The user mentions a budget or wants to constrain cost.

## How to invoke

Call the `research` MCP tool with:

| Field        | Required | Notes                                              |
| ------------ | -------- | -------------------------------------------------- |
| `question`   | yes      | The user's question, verbatim.                     |
| `budget_usd` | no       | Total USD cap across planner + workers (def 0.50). |

The tool returns JSON with three fields:

- `plan` — the planner's full decomposition (every sub-question + depth).
- `delegated` — which sub-questions actually got worker jobs and at
  what budget slice.
- `dropped` — sub-questions the planner skipped because the remaining
  budget no longer fit the requested grant. Surface these to the user
  if relevant — they represent capped work, not failed work.

## What runs under the hood

1. The MCP tool call enters the bridge process over stdio.
2. The bridge submits a `planner` job to the ARCP runtime with a
   `cost.budget` lease equal to `budget_usd`.
3. The planner emits `delegate` events for each sub-question, debiting
   its own budget after every grant so the runtime's lease-subset check
   stays honest at the next delegate.
4. Workers run independently, charging real token costs against their
   own slices. Some may trip `BudgetExhausted` mid-research — that is
   not a tool error; it is the cap doing its job.
5. The bridge awaits the planner's terminal result and returns it as
   the MCP tool's text response.

## Registering this skill

The skill itself is auto-discovered by the host (Claude Code looks under
`.claude/skills/` / `~/.claude/skills/`). The MCP server it points at
must be registered separately in the host's MCP config — for Claude
Desktop / Claude Code, that's something like:

```json
{
  "mcpServers": {
    "arcp-research-bridge": {
      "command": "bundle",
      "args": ["exec", "ruby", "recipes/mcp_skill/run.rb"]
    }
  }
}
```
