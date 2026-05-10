#!/usr/bin/env ruby
# frozen_string_literal: true

# Sample 01 — Minimal session.
#
# Opens a session, exchanges a ping/pong, and closes.

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'arcp'
require 'async'

CLIENT_IDENTITY = {
  kind: 'arcp-sample-01',
  version: Arcp::IMPL_VERSION,
  fingerprint: 'sha256:dev'
}.freeze

Sync do
  client_side, runtime_side = Arcp::Transport::Memory.pair
  bearer = Arcp::Auth::Bearer.new(accept_any: true)
  runtime = Arcp::Runtime::Runtime.new(schemes: [bearer])
  Async { runtime.serve(runtime_side) }

  client = Arcp::Client::Client.new(transport: client_side)
  begin
    accepted = client.open(
      auth: { scheme: 'bearer', token: 'sample-tok' },
      client: CLIENT_IDENTITY
    )
    puts "session_id=#{accepted[:session_id]}"
    puts "runtime=#{accepted[:runtime].inspect}"
    puts "ping pong received_at=#{client.ping}"
  ensure
    client.close
  end
end
