#!/usr/bin/env ruby
# frozen_string_literal: true

# Fan a request out to peer runtimes; tolerate partial failure.

require 'arcp'
require 'async'
require 'async/queue'
require 'securerandom'

require_relative 'synth'

PEERS = %w[research.web research.code research.docs].freeze
TERMINAL = %w[job.completed job.failed job.cancelled].to_set.freeze

Job = Struct.new(:target, :job_id, :final, :error, keyword_init: true)

def delegate(client, target:, task:, trace_id:)
  env = Arcp::Envelope.build(
    type: 'agent.delegate',
    trace_id: trace_id,
    payload: {
      target: target, task: task,
      # trace_id propagates so peers join one distributed trace.
      context: { 'trace_id' => trace_id }
    },
    session_id: client.session_id
  )
  client.send_envelope(env)
  accepted = client.receive_envelope
  if accepted.type != 'job.accepted'
    return Job.new(target: target, error: { code: accepted.payload[:code],
                                            message: accepted.payload[:message] })
  end
  Job.new(target: target, job_id: accepted.payload.job_id)
end

# Single reader on `client.receive_envelope`; fans out by `job_id`.
# Without this, parallel readers starve each other.
class JobMux
  def initialize(client)
    @client = client
    @queues = {}
  end

  def start
    @reader = Async do
      loop do
        env = @client.receive_envelope
        break if env.nil?

        jid = env.job_id&.value
        next unless jid && @queues.key?(jid)

        @queues[jid].enqueue(env)
        @queues[jid].enqueue(nil) if TERMINAL.include?(env.type)
      end
    end
  end

  def register(job_id) = @queues[job_id] = Async::Queue.new

  def stream(job)
    return if job.job_id.nil?

    q = @queues[job.job_id]
    while (env = q.dequeue)
      yield env
      break if TERMINAL.include?(env.type)
    end
  end
end

def collect(mux, job)
  return job if job.error

  mux.stream(job) do |env|
    case env.type
    when 'job.completed' then job.final = env.payload
    when 'job.failed' then job.error = { code: env.payload[:code], message: env.payload[:message] }
    when 'job.cancelled' then job.error = { code: 'CANCELLED', message: 'cancelled' }
    end
  end
  job
end

Sync do
  client = nil # ARCPClient(...) — transport, identity, auth elided
  client.open

  mux = JobMux.new(client)
  mux.start

  request = 'what changed in our auth stack in the last 30 days?'
  trace_id = "trace_#{SecureRandom.hex(6)}"

  jobs = PEERS.map do |peer|
    job = delegate(client, target: peer, task: request, trace_id: trace_id)
    mux.register(job.job_id) if job.job_id
    job
  end

  completed = jobs.map { |j| Async { collect(mux, j) } }.map(&:wait)
  puts Synth.synthesize(request, completed)

  client.close
end
