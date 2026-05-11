#!/usr/bin/env ruby
# frozen_string_literal: true

# Boot three Observer clients on a single producing session.

require 'arcp'
require 'async'

require_relative 'sinks/stdout_sink'
require_relative 'sinks/sqlite_sink'
require_relative 'sinks/otlp_sink'

STDOUT_TYPES = %w[log job.started job.progress job.completed job.failed
                  tool.error].freeze
OTLP_TYPES = %w[metric trace.span].freeze

def subscribe(client, session_id:, types: nil)
  filter = { 'session_id' => [session_id] }
  filter['types'] = types if types
  envelope = Arcp::Envelope.build(
    type: 'subscribe',
    payload: Arcp::Messages::Subscriptions::Subscribe.new(filter: filter, since: nil),
    session_id: client.session_id
  )
  client.send_envelope(envelope)
  accepted = client.receive_envelope
  accepted.payload.subscription_id
end

def unwrap_event(envelope)
  return nil unless envelope.type == 'subscribe.event'

  inner = envelope.payload.event
  return nil unless inner.is_a?(Hash)

  inner
end

def unsubscribe(client, subscription_id)
  env = Arcp::Envelope.build(
    type: 'unsubscribe',
    payload: { subscription_id: subscription_id },
    session_id: client.session_id
  )
  client.send_envelope(env)
end

def attach(types, handler)
  client = nil # ARCPClient(...) — transport, identity, auth elided
  client.open
  sub_id = subscribe(client, session_id: '...', types: types)
  begin
    loop do
      env = client.receive_envelope
      break if env.nil?

      inner = unwrap_event(env)
      handler.call(inner) if inner
    end
  ensure
    unsubscribe(client, sub_id)
    client.close
  end
end

Sync do
  stdout = StdoutSink.new
  otlp = OTLPSink.new(endpoint: '...')
  SQLiteSink.open(path: 'replay.sqlite') do |sqlite|
    Async { attach(STDOUT_TYPES, stdout.method(:handle)) }
    Async { attach(nil, sqlite.method(:handle)) }
    Async { attach(OTLP_TYPES, otlp.method(:handle)) }
  end
end
