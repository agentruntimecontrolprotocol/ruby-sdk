# frozen_string_literal: true

# Upstream MCP server invocation.
#
# Real version parameterizes command, args, env via your config layer.
# Reference servers from the modelcontextprotocol org publish under
# `mcp-server-*` (filesystem, git, postgres, slack, ...).
module Upstream
  StdioParams = Data.define(:command, :args)

  def self.params
    StdioParams.new(command: 'uvx', args: ['mcp-server-filesystem', '/srv/data'])
  end
end
