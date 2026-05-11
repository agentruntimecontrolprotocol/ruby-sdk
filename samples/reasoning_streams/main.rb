#!/usr/bin/env ruby
# frozen_string_literal: true

# Primary emits reasoning; mirror peer subscribes, critiques back.

require 'arcp'
require 'async'
require 'async/queue'
require 'securerandom'

require_relative 'agents'

MAX_DEPTH = 3
TOKEN_BUDGET = 8_000

# Primary side -----------------------------------------------------------

def run_primary(client, request:, inbound_critiques:)
  stream_id = "str_#{SecureRandom.hex(5)}"
  open_env = Arcp::Envelope.build(
    type: 'stream.open',
    payload: Arcp::Messages::Streaming::StreamOpen.new(kind: 'thought'),
    stream_id: stream_id, session_id: client.session_id
  )
  client.send_envelope(open_env)

  last = nil
  answer = ''
  MAX_DEPTH.times do |step|
    answer = Agents.primary_step(request, last)
    chunk = Arcp::Envelope.build(
      type: 'stream.chunk',
      payload: Arcp::Messages::Streaming::StreamChunk.new(
        sequence: step, kind: 'thought', role: 'assistant_thought', content: answer
      ),
      stream_id: stream_id, session_id: client.session_id
    )
    client.send_envelope(chunk)

    last = inbound_critiques.dequeue_with_timeout(5.0)
    break if last && last[:severity] == 'halt'
  end
  answer
end

# Mirror side (a peer runtime, NOT a pure observer — both reads the
# thought stream AND delegates critique events back) --------------------

def subscribe_thoughts(mirror, target_session_id:)
  env = Arcp::Envelope.build(
    type: 'subscribe',
    payload: Arcp::Messages::Subscriptions::Subscribe.new(
      filter: { 'session_id' => [target_session_id], 'types' => ['stream.chunk'] },
      since: nil
    ),
    session_id: mirror.session_id
  )
  mirror.send_envelope(env)
  mirror.receive_envelope.payload.subscription_id
end

def thought?(env)
  return false unless env['type'] == 'stream.chunk'

  payload = env['payload'] || {}
  payload['kind'] == 'thought' || payload['role'] == 'assistant_thought'
end

def run_mirror(mirror, target_session_id:)
  sub_id = subscribe_thoughts(mirror, target_session_id: target_session_id)
  spent = 0
  begin
    loop do
      env = mirror.receive_envelope
      break if env.nil?
      next unless env.type == 'subscribe.event'

      inner = env.payload.event
      next unless inner.is_a?(Hash) && thought?(inner)

      if spent >= TOKEN_BUDGET
        # Tear down cleanly: runtime stops paying for events
        # we'll never act on.
        mirror.send_envelope(Arcp::Envelope.build(
                               type: 'unsubscribe',
                               payload: { subscription_id: sub_id },
                               session_id: mirror.session_id
                             ))
        return
      end

      severity, summary, suggestion, consumed =
        Agents.critique_thought(inner.dig('payload', 'content').to_s)
      spent += consumed
      delegate = Arcp::Envelope.build(
        type: 'agent.delegate',
        target: target_session_id,
        payload: {
          target: 'primary', task: 'consume_critique',
          context: {
            critique: {
              target_thought_sequence: inner.dig('payload', 'sequence').to_i,
              severity: severity, summary: summary,
              suggestion: suggestion, consumed_tokens: consumed
            }
          }
        },
        session_id: mirror.session_id
      )
      mirror.send_envelope(delegate)
    end
  ensure
    mirror.send_envelope(Arcp::Envelope.build(
                           type: 'unsubscribe',
                           payload: { subscription_id: sub_id },
                           session_id: mirror.session_id
                         ))
  end
end

# Async::Queue ext: dequeue with timeout (returns nil on timeout).
class Async::Queue
  def dequeue_with_timeout(seconds)
    Async do |task|
      task.with_timeout(seconds) { dequeue }
    rescue Async::TimeoutError
      nil
    end.wait
  end
end

Sync do
  primary = nil # ARCPClient(...)
  mirror  = nil # ARCPClient(...)
  primary.open
  mirror.open

  inbound = Async::Queue.new

  # Both run for the lifetime of the block.
  Async do
    loop do
      env = primary.receive_envelope
      break if env.nil?
      next unless env.type == 'agent.delegate'

      critique = env.payload.dig(:context, :critique) || env.payload.dig('context', 'critique')
      inbound.enqueue(critique) if critique.is_a?(Hash)
    end
  end
  Async { run_mirror(mirror, target_session_id: primary.session_id&.value || '') }

  answer = run_primary(
    primary,
    request: 'Argue both sides: serializable vs snapshot iso?',
    inbound_critiques: inbound
  )
  puts answer

  primary.close
  mirror.close
end
