#!/usr/bin/env ruby
# frozen_string_literal: true

# Two scenarios over the §10.4 / §10.5 control surface.

require 'arcp'
require 'async'

CANCEL_DEADLINE_MS = 5_000

def start_long_job(client)
  env = Arcp::Envelope.build(
    type: 'tool.invoke',
    payload: Arcp::Messages::Execution::ToolInvoke.new(
      tool: 'demo.long_running', arguments: { work_seconds: 600 }
    ),
    session_id: client.session_id
  )
  client.send_envelope(env)
  accepted = client.receive_envelope
  accepted.payload.job_id
end

# Cooperative cancel. Runtime drives target to a clean checkpoint
# inside `deadline_ms` before terminating; escalates to ABORTED on
# timeout (RFC §10.4).
def cancel_job(client, job_id:, reason:, deadline_ms:)
  env = Arcp::Envelope.build(
    type: 'cancel',
    payload: Arcp::Messages::Control::Cancel.new(
      target: 'job', target_id: job_id, reason: reason, deadline_ms: deadline_ms
    ),
    session_id: client.session_id, job_id: job_id
  )
  client.send_envelope(env)
  reply = client.receive_envelope
  if reply.type == 'cancel.refused'
    raise Arcp::Error::FailedPrecondition,
          (reply.payload[:reason] || reply.payload['reason'] || 'cancel refused')
  end

  reply
end

# Distinct from cancel: pauses the job (`blocked`); runtime emits
# `human.input.request`. Job is NOT terminated (RFC §10.5).
def interrupt_job(client, job_id:, prompt:)
  env = Arcp::Envelope.build(
    type: 'interrupt',
    payload: Arcp::Messages::Control::Interrupt.new(
      target: 'job', target_id: job_id, prompt: prompt
    ),
    session_id: client.session_id, job_id: job_id
  )
  client.send_envelope(env)
end

def await_terminal(client, job_id:)
  loop do
    env = client.receive_envelope
    break if env.nil?
    next if env.job_id&.value != job_id

    return env if %w[job.completed job.failed job.cancelled].include?(env.type)
  end
  raise 'event stream closed before terminal'
end

def scenario_cancel
  client = nil # ARCPClient(...)
  client.open
  begin
    job_id = start_long_job(client)
    sleep 2 # let the job actually start
    ack = cancel_job(client, job_id: job_id, reason: 'user_aborted',
                             deadline_ms: CANCEL_DEADLINE_MS)
    puts "cancel ack: #{ack.type}"
    terminal = await_terminal(client, job_id: job_id)
    puts "terminal: #{terminal.type} code=#{terminal.payload[:code]}"
  ensure
    client.close
  end
end

def scenario_interrupt
  client = nil # ARCPClient(...)
  client.open
  begin
    job_id = start_long_job(client)
    sleep 2
    interrupt_job(client, job_id: job_id,
                          prompt: 'Pause and ask before touching production tables.')
    # Runtime now emits human.input.request; answer via samples/human_input.
    loop do
      env = client.receive_envelope
      break if env.nil?
      next unless env.type == 'human.input.request' && env.job_id&.value == job_id

      puts "awaiting human: #{env.payload.prompt.inspect}"
      return
    end
  ensure
    client.close
  end
end

Sync do
  case ARGV.first || 'cancel'
  when 'cancel'    then scenario_cancel
  when 'interrupt' then scenario_interrupt
  else raise "unknown scenario: #{ARGV.first}"
  end
end
