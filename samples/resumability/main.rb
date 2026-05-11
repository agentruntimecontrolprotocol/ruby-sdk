#!/usr/bin/env ruby
# frozen_string_literal: true

# Durable research job with real crash and resume.
#
#   # First call: crash after `synthesize`. Prints the resume token.
#   CRASH_AFTER_STEP=synthesize ruby samples/resumability/main.rb
#
#   # Second call: pick up from the printed checkpoint.
#   RESUME_JOB_ID=... RESUME_AFTER_MSG_ID=... RESUME_CHECKPOINT_ID=... \
#     ruby samples/resumability/main.rb

require 'arcp'
require 'async'
require 'digest'
require 'securerandom'

require_relative 'steps'

STEPS = %w[plan gather synthesize critique finalize].freeze

# Deterministic per-step idempotency key (RFC §6.4). Re-issuing the
# same step with the same input returns the prior outcome instead of
# re-running the LLM.
def step_key(job_id:, step:, salt:)
  h = Digest::SHA256.new
  [job_id, step, salt].each do |piece|
    h.update(piece)
    h.update("\x00")
  end
  "research:#{job_id}:#{step}:#{h.hexdigest[0, 16]}"
end

def emit_progress(client, job_id:, step:)
  pct = 100.0 * (STEPS.index(step) + 1) / STEPS.length
  env = Arcp::Envelope.build(
    type: 'job.progress', job_id: job_id,
    payload: { percent: pct, message: step },
    session_id: client.session_id
  )
  client.send_envelope(env)
end

def emit_checkpoint(client, job_id:, step:)
  chk = "chk_#{step}_#{job_id[-6..]}"
  env = Arcp::Envelope.build(
    type: 'job.checkpoint', job_id: job_id,
    payload: { checkpoint_id: chk, label: step },
    session_id: client.session_id
  )
  client.send_envelope(env)
  chk
end

def execute_steps(client, job_id:, request:, starting_at:, crash_after:)
  output = request
  STEPS.each do |step|
    next if STEPS.index(step) < STEPS.index(starting_at)

    key = step_key(job_id: job_id, step: step, salt: output.inspect)
    emit_progress(client, job_id: job_id, step: step)
    output = Steps.run_step(client, job_id: job_id, step: step,
                                    inputs: { prior: output, idempotency_key: key })
    emit_checkpoint(client, job_id: job_id, step: step)
    next unless crash_after == step

    # The whole point of durable jobs: process death is fine.
    # Runtime kept every envelope; resume picks it up.
    warn("[crash after #{step}; resume with " \
         "RESUME_JOB_ID=#{job_id} " \
         "RESUME_CHECKPOINT_ID=chk_#{step}_#{job_id[-6..]} " \
         'RESUME_AFTER_MSG_ID=<last id from your event log>]')
    Process.exit!(137)
  end
  output
end

# Replay envelopes; return the last checkpoint label, or nil if the
# job already terminated during replay.
def issue_resume(client, job_id:, after_message_id:, checkpoint_id:)
  payload = { after_message_id: after_message_id, include_open_streams: true }
  payload[:checkpoint_id] = checkpoint_id if checkpoint_id
  resume = Arcp::Envelope.build(
    type: 'resume', job_id: job_id, payload: payload,
    session_id: client.session_id
  )
  client.send_envelope(resume)

  last = nil
  loop do
    env = client.receive_envelope
    break if env.nil?
    next if env.job_id&.value != job_id

    case env.type
    when 'tool.error'
      raise Arcp::Error::DataLoss, 'retention expired' if env.payload[:code] == Arcp::ErrorCode::DATA_LOSS
    when 'job.checkpoint'
      last = env.payload[:label]
    when 'job.completed', 'job.failed', 'job.cancelled'
      return nil
    when 'event.emit'
      return last if env.payload[:name] == 'subscription.backfill_complete'
    end
  end
  last
end

Sync do
  client = nil # ARCPClient(...) — transport, identity, auth elided
  client.open

  rj_id = ENV.fetch('RESUME_JOB_ID', nil)
  rj_after = ENV.fetch('RESUME_AFTER_MSG_ID', nil)
  if rj_id && rj_after
    last = issue_resume(client, job_id: rj_id, after_message_id: rj_after,
                                checkpoint_id: ENV.fetch('RESUME_CHECKPOINT_ID', nil))
    if last.nil?
      puts 'already terminal during replay'
    else
      next_idx = STEPS.index(last) + 1
      if next_idx >= STEPS.length
        puts 'nothing to resume'
      else
        puts "[resuming at #{STEPS[next_idx]}]"
        final = execute_steps(client, job_id: rj_id, request: '<replayed>',
                                      starting_at: STEPS[next_idx], crash_after: nil)
        done = Arcp::Envelope.build(type: 'job.completed', job_id: rj_id,
                                    payload: { result: final },
                                    session_id: client.session_id)
        client.send_envelope(done)
      end
    end
  else
    job_id = "job_#{SecureRandom.hex(6)}"
    request = 'Survey CRDT-based collaborative editing in 2026.'
    start = Arcp::Envelope.build(
      type: 'workflow.start', job_id: job_id,
      payload: { workflow: 'research.v1', arguments: { request: request } },
      session_id: client.session_id
    )
    client.send_envelope(start)
    final = execute_steps(client, job_id: job_id, request: request,
                                  starting_at: STEPS.first,
                                  crash_after: ENV.fetch('CRASH_AFTER_STEP', nil))
    done = Arcp::Envelope.build(type: 'job.completed', job_id: job_id,
                                payload: { result: final },
                                session_id: client.session_id)
    client.send_envelope(done)
    puts "job_id=#{job_id}\n#{final}"
  end

  client.close
end
