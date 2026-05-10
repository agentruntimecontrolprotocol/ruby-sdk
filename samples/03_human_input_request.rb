#!/usr/bin/env ruby
# frozen_string_literal: true

# Sample 03 — Human input request.
#
# A tool asks the human (via the client) for a JSON-validated value;
# the client supplies the response.

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'arcp'
require 'async'

CLIENT_IDENTITY = {
  kind: 'arcp-sample-03',
  version: Arcp::IMPL_VERSION,
  fingerprint: 'sha256:dev'
}.freeze

Sync do
  client_side, runtime_side = Arcp::Transport::Memory.pair
  bearer = Arcp::Auth::Bearer.new(accept_any: true)
  runtime = Arcp::Runtime::Runtime.new(schemes: [bearer])
  runtime.register_tool('open-pr') do |ctx, _args|
    answer = ctx.request_human_input(
      prompt: 'Branch name for the fix?',
      response_schema: { 'type' => 'object',
                         'properties' => { 'branch' => { 'type' => 'string', 'minLength' => 1 } },
                         'required' => ['branch'] },
      default: { 'branch' => 'fix/auto' }
    )
    { opened_branch: answer['branch'] }
  end
  Async { runtime.serve(runtime_side) }

  client = Arcp::Client::Client.new(transport: client_side)
  client.open(auth: { scheme: 'bearer', token: 'tok' }, client: CLIENT_IDENTITY)
  client.on_human_input { |env| { 'branch' => "fix/#{env.payload.prompt[/Branch name for the (.+)\?/, 1] || 'pr'}" } }

  result = client.invoke(tool: 'open-pr')
  puts "answered=#{result.value.inspect}"
  client.close
end
