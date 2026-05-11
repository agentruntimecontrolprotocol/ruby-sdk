#!/usr/bin/env ruby
# frozen_string_literal: true

# Fan `human.input.request` across channels; resolve on first.

require 'arcp'
require 'async'
require 'time'

require_relative 'channels'

DESTINATIONS = %w[ntfy:phone email:oncall slack:ops].freeze

def parse_iso(value) = Time.iso8601(value)

def fan_out(client, request)
  payload = request.payload
  schema = payload.respond_to?(:response_schema) ? payload.response_schema : (payload[:response_schema] || {})
  prompt = payload.respond_to?(:prompt) ? payload.prompt : payload[:prompt].to_s
  expires_at = parse_iso(payload.respond_to?(:expires_at) ? payload.expires_at : payload[:expires_at])
  timeout = [0.0, expires_at - Time.now.utc].max

  tasks = DESTINATIONS.to_h do |dest|
    [Async { [dest, Channels::REGISTRY.fetch(dest).call(prompt, schema)] }, dest]
  end

  winner = nil
  Async do |task|
    task.with_timeout(timeout) do
      winner = tasks.keys.find { |t| t.wait && true }
    end
  rescue Async::TimeoutError
    nil
  end.wait
  tasks.each_key { |t| t.stop unless t.finished? }

  unless winner
    # Deadline elapsed; translate timeout into the cancelled-input
    # shape (RFC §12.4).
    client.send_envelope(Arcp::Envelope.build(
                           type: 'human.input.cancelled',
                           correlation_id: request.id,
                           payload: { code: Arcp::ErrorCode::DEADLINE_EXCEEDED,
                                      message: 'no channel responded before expires_at' },
                           session_id: client.session_id
                         ))
    return
  end

  responded_by, value = winner.wait
  client.send_envelope(Arcp::Envelope.build(
                         type: 'human.input.response',
                         correlation_id: request.id,
                         payload: { value: value, responded_by: responded_by,
                                    responded_at: Time.now.utc.iso8601 },
                         session_id: client.session_id
                       ))

  # Tell losing destinations the question is settled. Each channel
  # adapter would translate this to "delete the push" / "edit the
  # slack message to '(answered)'".
  losers = tasks.reject { |t, _| t == winner }.values
  return if losers.empty?

  client.send_envelope(Arcp::Envelope.build(
                         type: 'human.input.cancelled',
                         correlation_id: request.id,
                         payload: { code: Arcp::ErrorCode::OK,
                                    message: 'answered elsewhere',
                                    channels: losers },
                         session_id: client.session_id
                       ))
end

Sync do
  client = nil # ARCPClient(...) — transport, identity, auth elided
  client.open
  begin
    loop do
      env = client.receive_envelope
      break if env.nil?

      Async { fan_out(client, env) } if env.type == 'human.input.request'
    end
  ensure
    client.close
  end
end
