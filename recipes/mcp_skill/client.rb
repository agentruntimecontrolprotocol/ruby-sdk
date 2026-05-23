# frozen_string_literal: true

# mcp_skill client — simulates an MCP host issuing a `tools/call` for `research`.
#
# A real MCP host (Claude Code, Cursor, Desktop) speaks JSON-RPC over
# stdio to the bridge process. Here we wire the bridge in-process and
# call `handle_request` directly to keep the recipe self-contained.

require 'json'
require_relative '../../samples/_harness'
require_relative 'server'

module McpSkillRecipe
  module Client
    def self.run(arcp_client)
      # `tools/list` — what the MCP host would advertise to the model.
      tools = McpSkillRecipe.handle_request(
        { 'jsonrpc' => '2.0', 'id' => 1, 'method' => 'tools/list' },
        arcp_client: arcp_client
      )

      # `tools/call` — the model has decided to invoke `research`.
      call = McpSkillRecipe.handle_request(
        {
          'jsonrpc' => '2.0', 'id' => 2, 'method' => 'tools/call',
          'params' => {
            'name' => 'research',
            'arguments' => { 'question' => 'What causes urban heat islands?', 'budget_usd' => 0.5 }
          }
        },
        arcp_client: arcp_client
      )

      [tools, call]
    end
  end
end
