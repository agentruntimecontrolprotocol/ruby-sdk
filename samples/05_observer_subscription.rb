#!/usr/bin/env ruby
# frozen_string_literal: true

# Sample 05 — Observer subscription.
#
# Run a tool that emits progress, then subscribe and replay the events
# via the subscription mechanism.

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'arcp'
require 'async'

CLIENT_IDENTITY = {
  kind: 'arcp-sample-05',
  version: Arcp::IMPL_VERSION,
  fingerprint: 'sha256:dev'
}.freeze

Sync do
  client_side, runtime_side = Arcp::Transport::Memory.pair
  bearer = Arcp::Auth::Bearer.new(accept_any: true)
  runtime = Arcp::Runtime::Runtime.new(schemes: [bearer])
  runtime.register_tool('counter') do |ctx, _args|
    3.times { |i| ctx.progress(percent: (i + 1) * 33, message: "step-#{i + 1}") }
    :done
  end
  Async { runtime.serve(runtime_side) }

  client = Arcp::Client::Client.new(transport: client_side)
  client.open(auth: { scheme: 'bearer', token: 'tok' }, client: CLIENT_IDENTITY)
  client.invoke(tool: 'counter')

  sub = Arcp::Envelope.build(
    type: 'subscribe',
    payload: Arcp::Messages::Subscriptions::Subscribe.new(
      filter: { 'session_id' => [client.session_id.value], 'types' => ['job.progress'] },
      since: nil
    ),
    session_id: client.session_id
  )
  client_side.send_envelope(sub)
  accepted = client_side.receive_envelope
  puts "subscription accepted: #{accepted.payload.subscription_id}"

  loop do
    env = client_side.receive_envelope
    break if env.nil?

    payload = env.payload
    next unless payload.is_a?(Arcp::Messages::Subscriptions::SubscribeEvent)

    inner_payload = payload.event[:payload] || payload.event['payload']
    if (inner_payload.is_a?(Hash) && inner_payload[:name] == 'subscription.backfill_complete')
      puts 'backfill complete'
      break
    end

    inner_type = payload.event[:type] || payload.event['type']
    puts "observed: #{inner_type} #{inner_payload.inspect}"
  end
  client.close
end
