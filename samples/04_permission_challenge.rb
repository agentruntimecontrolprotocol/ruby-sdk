#!/usr/bin/env ruby
# frozen_string_literal: true

# Sample 04 — Permission challenge.
#
# A tool requests a scoped permission, the client grants it, the tool
# completes and the runtime emits lease.granted along the way.

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'arcp'
require 'async'

CLIENT_IDENTITY = {
  kind: 'arcp-sample-04',
  version: Arcp::IMPL_VERSION,
  fingerprint: 'sha256:dev'
}.freeze

Sync do
  client_side, runtime_side = Arcp::Transport::Memory.pair
  bearer = Arcp::Auth::Bearer.new(accept_any: true)
  runtime = Arcp::Runtime::Runtime.new(schemes: [bearer])
  runtime.register_tool('refund') do |ctx, args|
    lease = ctx.request_permission(
      permission: 'payment.refund.create',
      resource: "order:#{args[:order_id]}",
      operation: 'refund',
      reason: 'customer-approved refund',
      requested_lease_seconds: 60
    )
    { lease_id: lease.lease_id.value, expires_at: lease.expires_at.iso8601 }
  end
  Async { runtime.serve(runtime_side) }

  client = Arcp::Client::Client.new(transport: client_side)
  client.open(auth: { scheme: 'bearer', token: 'tok' }, client: CLIENT_IDENTITY)
  client.on_permission_request do |env|
    puts "permission requested: #{env.payload.permission} on #{env.payload.resource}"
    :grant
  end

  result = client.invoke(tool: 'refund', arguments: { order_id: 'ord_4812' })
  puts "lease=#{result.value.inspect}"
  client.close
end
