#!/usr/bin/env ruby
# frozen_string_literal: true

# Capability-driven peer routing with ordered fallback + cost rollup.

require 'arcp'
require 'async'
require 'securerandom'

PEERS = %w[anthropic-haiku anthropic-sonnet openai-4o groq-llama].freeze
FALLBACK_CHAINS = {
  'cheap_fast' => %w[groq-llama anthropic-haiku openai-4o],
  'balanced' => %w[anthropic-sonnet openai-4o anthropic-haiku],
  'deep' => %w[anthropic-sonnet]
}.freeze
COST_CEILING_USD_PER_MTOK = 8.0
LATENCY_CEILING_MS = 800
RETRYABLE = [
  Arcp::ErrorCode::RESOURCE_EXHAUSTED, Arcp::ErrorCode::UNAVAILABLE,
  Arcp::ErrorCode::DEADLINE_EXCEEDED, Arcp::ErrorCode::ABORTED
].to_set.freeze

Profile = Data.define(:cost_per_mtok, :p50_latency_ms, :model_class)

# Capabilities is `extra: allow` so namespaced fields ride alongside
# the core booleans. NOTE: §21 covers extension *messages* but not
# extension *capability values* — load-bearing convention here.
def profile_from(caps)
  extra = caps[:extensions] || {}
  Profile.new(
    cost_per_mtok: (extra['arcpx.market.cost_per_mtok.v1'] || 0.0).to_f,
    p50_latency_ms: (extra['arcpx.market.p50_latency_ms.v1'] || 0).to_i,
    model_class: (extra['arcpx.market.model_class.v1'] || 'unknown').to_s
  )
end

def candidate_chain(profiles, request_class)
  (FALLBACK_CHAINS[request_class] || []).select do |name|
    p = profiles[name]
    p && p.cost_per_mtok <= COST_CEILING_USD_PER_MTOK &&
      p.p50_latency_ms <= LATENCY_CEILING_MS
  end
end

# Walk the chain. Retryable error -> next peer; otherwise raise.
def invoke_with_fallback(clients:, chain:, tool:, arguments:, trace_id:)
  last = nil
  chain.each do |name|
    client = clients[name]
    begin
      env = Arcp::Envelope.build(
        type: 'tool.invoke',
        trace_id: trace_id,
        extensions: { 'arcpx.market.peer.v1' => name },
        payload: Arcp::Messages::Execution::ToolInvoke.new(tool: tool, arguments: arguments),
        session_id: client.session_id
      )
      client.send_envelope(env)
      reply = client.receive_envelope
    rescue Arcp::Error => e
      last = e
      next if RETRYABLE.include?(e.code)

      raise
    end
    return reply unless reply.type == 'tool.error'

    code = reply.payload[:code] || reply.payload['code']
    last = Arcp::Error.new(reply.payload[:message].to_s)
    next if RETRYABLE.include?(code)

    raise last
  end
  raise(last || Arcp::Error::Unavailable.new('no peers available'))
end

Usage = Struct.new(:tokens_in, :tokens_out, :cost_usd, :by_peer)

def consume_metric(env, totals)
  return unless env.type == 'metric'

  p = env.payload
  dims = p[:dims] || {}
  name = p[:name]
  value = p[:value]
  return unless value.is_a?(Numeric)

  u = (totals[dims['tenant'] || 'unknown'] ||= Usage.new(0, 0, 0.0, {}))
  case name
  when 'tokens.used'
    case dims['kind']
    when 'input'  then u.tokens_in  += value.to_i
    when 'output' then u.tokens_out += value.to_i
    end
  when 'cost.usd'
    u.cost_usd += value.to_f
    peer = dims['peer'] || 'unknown'
    u.by_peer[peer] = (u.by_peer[peer] || 0.0) + value.to_f
  end
end

Sync do
  clients = {}
  profiles = {}
  PEERS.each do |name|
    c = nil # ARCPClient(...) — transport per peer URL, identity, auth elided
    accepted = c.open
    clients[name] = c
    # Marketplace fields ride on the negotiated capabilities;
    # no extra round trip to learn cost / latency / class.
    profiles[name] = profile_from(accepted[:capabilities])
  end

  totals = {}
  drains = clients.values.map do |c|
    Async do
      loop do
        env = c.receive_envelope
        break if env.nil?

        consume_metric(env, totals)
      end
    end
  end

  chain = candidate_chain(profiles, 'balanced')
  reply = invoke_with_fallback(
    clients: clients, chain: chain, tool: 'chat.completion',
    arguments: { prompt: 'Hello', tenant: 'acme-corp' },
    trace_id: "trace_#{SecureRandom.hex(6)}"
  )
  puts "chosen=#{(reply.extensions || {})['arcpx.market.peer.v1']}"
  puts "usage=#{totals.inspect}"

  drains.each(&:stop)
  clients.each_value(&:close)
end
