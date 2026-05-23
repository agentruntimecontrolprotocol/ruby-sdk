# frozen_string_literal: true

require_relative 'server'
require_relative 'client'

code = Harness.run_or_exit('mcp_skill') do |emit|
  server_t, client_t = Harness.pair_memory
  runtime = McpSkillRecipe.runtime
  arcp_client, task = Harness.open_client(server_t, client_t, runtime, client_name: 'mcp-bridge')

  tools, call = McpSkillRecipe::Client.run(arcp_client)
  tool_names = tools.dig('result', 'tools')&.map { |t| t['name'] } || []
  content = call.dig('result', 'content') || []

  emit.call(
    'tools_advertised' => tool_names,
    'call_returned_blocks' => content.size,
    'first_block_type' => content.first&.dig('type')
  )
  arcp_client.close
  task.stop
end
exit code
