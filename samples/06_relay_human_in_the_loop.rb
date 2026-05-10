#!/usr/bin/env ruby
# frozen_string_literal: true

# Sample 06 — Relay scenario.
#
# Demonstrates the full agent-relay workflow:
#   1. Tool starts a job
#   2. Tool requests human input
#   3. Tool requests a permission, gets a lease, completes
#   4. Client observes the entire stream including lease.granted
#   5. The session is closed

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'arcp'
require 'async'

CLIENT_IDENTITY = {
  kind: 'arcp-sample-06',
  version: Arcp::IMPL_VERSION,
  fingerprint: 'sha256:dev'
}.freeze

Sync do
  client_side, runtime_side = Arcp::Transport::Memory.pair
  bearer = Arcp::Auth::Bearer.new(accept_any: true)
  runtime = Arcp::Runtime::Runtime.new(schemes: [bearer])
  runtime.register_tool('relay') do |ctx, _args|
    confirm = ctx.request_human_input(
      prompt: 'Proceed with refund?',
      response_schema: { 'type' => 'object',
                         'properties' => { 'confirm' => { 'type' => 'boolean' } },
                         'required' => ['confirm'] }
    )
    raise Arcp::Error::Cancelled, 'user declined' unless confirm['confirm']

    lease = ctx.request_permission(
      permission: 'payment.refund.create',
      resource: 'order:42',
      operation: 'refund',
      requested_lease_seconds: 60
    )
    { ok: true, lease_id: lease.lease_id.value }
  end
  Async { runtime.serve(runtime_side) }

  client = Arcp::Client::Client.new(transport: client_side)
  client.open(auth: { scheme: 'bearer', token: 'tok' }, client: CLIENT_IDENTITY)
  client.on_human_input { |_env| { 'confirm' => true } }
  client.on_permission_request { |_env| :grant }

  result = client.invoke(tool: 'relay')
  puts "events:"
  result.events.each { |env| puts "  #{env.type}" }
  puts "value=#{result.value.inspect}"
  client.close
end
