# frozen_string_literal: true

# mcp_skill — bridge an MCP `research` tool to the multi_agent_budget planner.
#
# A minimal MCP server that bridges to the multi_agent_budget runtime,
# exposing the ARCP planner as a single `research` tool. The Claude
# Code skill in skills/research/SKILL.md describes when to invoke the
# tool; this file is the runtime bridge it ends up calling.
#
# Highlights: the seam between MCP (model-side tool surface) and ARCP
# (runtime-side agent execution). One long-lived ARCP session per MCP
# process; each MCP tool call submits a fresh ARCP job through it. The
# agent's eventual lease, cost cap, and delegation tree are entirely
# ARCP concerns — MCP just sees one call in, one result out.
#
# The MCP protocol surface itself is implemented inline against stdio
# JSON-RPC (one-message-per-line) to avoid pinning a particular Ruby
# MCP gem. Swap for `mcp` or any community client of your choice; only
# `list_tools` and `call_tool` are wired below.

require 'json'
require_relative '../../samples/_harness'
require_relative '../multi_agent_budget/server'

module McpSkillRecipe
  RESEARCH_TOOL = {
    'name' => 'research',
    'description' => 'Decompose a research question into sub-questions and answer ' \
                     'each under a shared cost cap. Returns the plan, delegated ' \
                     'sub-questions, and any dropped for budget.',
    'inputSchema' => {
      'type' => 'object',
      'properties' => {
        'question' => { 'type' => 'string' },
        'budget_usd' => { 'type' => 'number', 'default' => 0.5 }
      },
      'required' => ['question']
    }
  }.freeze

  # Forward an MCP `tools/call` into a fresh ARCP planner job and shape
  # the terminal result back as an MCP text content block.
  def self.call_research(arcp_client:, arguments:)
    budget = (arguments['budget_usd'] || 0.5).to_f
    handle = arcp_client.submit_job(
      agent: 'planner',
      input: { 'question' => arguments.fetch('question') },
      lease_request: Arcp::Lease::LeaseRequest.new(
        capabilities: ['tool.call:llm.complete', 'agent.delegate:worker'],
        budget: Arcp::Lease::CostBudget.parse(["USD:#{format('%.2f', budget)}"]),
        model_use: nil,
        expires_at: nil
      )
    )
    handle.subscribe(client: arcp_client).to_a
    result = handle.get_result(client: arcp_client)
    [{ 'type' => 'text', 'text' => JSON.pretty_generate(result.result) }]
  end

  # Tiny JSON-RPC reader/writer driving stdio. Pumps requests through
  # the handler block; `arcp_client` is forwarded into call_research.
  def self.run_stdio(arcp_client:, input: $stdin, output: $stdout)
    output.sync = true
    while (line = input.gets)
      request = JSON.parse(line)
      reply = handle_request(request, arcp_client: arcp_client)
      output.puts(JSON.dump(reply))
    end
  end

  def self.handle_request(request, arcp_client:)
    id = request['id']
    case request['method']
    when 'tools/list'
      { 'jsonrpc' => '2.0', 'id' => id, 'result' => { 'tools' => [RESEARCH_TOOL] } }
    when 'tools/call'
      params = request['params'] || {}
      raise "unknown tool: #{params['name']}" unless params['name'] == 'research'

      content = call_research(arcp_client: arcp_client, arguments: params.fetch('arguments'))
      { 'jsonrpc' => '2.0', 'id' => id, 'result' => { 'content' => content } }
    else
      { 'jsonrpc' => '2.0', 'id' => id, 'error' => { 'code' => -32_601, 'message' => 'method not found' } }
    end
  end

  # The bridge keeps one long-lived ARCP session for the lifetime of
  # the MCP process; each tool call submits a fresh job through it.
  def self.runtime = MultiAgentBudgetRecipe.runtime
end
