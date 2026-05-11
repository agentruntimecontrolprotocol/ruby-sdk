#!/usr/bin/env ruby
# frozen_string_literal: true

# Supervisor + worker pool. Heartbeat loss reroutes via idempotency_key.

require 'arcp'
require 'async'
require 'securerandom'
require 'time'

require_relative 'work'

HEARTBEAT_INTERVAL_SECONDS = 15
DEADLINE_S = HEARTBEAT_INTERVAL_SECONDS * 2 # RFC §10.3 default N=2

Worker = Struct.new(:worker_id, :role, :last_heartbeat, :in_flight_job, keyword_init: true)
Task = Data.define(:task_id, :role, :payload, :idempotency_key)

class Roster
  attr_reader :workers, :by_role

  def initialize
    @workers = {}
    @by_role = Hash.new { |h, k| h[k] = [] }
  end

  def add(worker)
    @workers[worker.worker_id] = worker
    @by_role[worker.role] << worker.worker_id
  end

  def candidates(role)
    (@by_role[role] || []).map { |wid| @workers[wid] }.select { |w| w.in_flight_job.nil? }
  end
end

# Supervisor side --------------------------------------------------------

def dispatch(client, task:, roster:, jobs_to_tasks:)
  candidates = roster.candidates(task.role)
  raise "no idle workers for role=#{task.role}" if candidates.empty?

  worker = candidates.min_by(&:last_heartbeat)
  # Same idempotency_key on every re-dispatch (RFC §6.4): a worker that
  # survived the network blip dedupes; it doesn't re-execute.
  env = Arcp::Envelope.build(
    type: 'agent.delegate',
    idempotency_key: task.idempotency_key,
    payload: {
      target: worker.worker_id, task: task.task_id,
      context: { task_payload: task.payload }
    },
    session_id: client.session_id
  )
  client.send_envelope(env)
  accepted = client.receive_envelope
  worker.in_flight_job = accepted.payload[:job_id]
  jobs_to_tasks[worker.in_flight_job] = task
end

def supervise(client, roster, jobs_to_tasks)
  Async do
    loop do
      sleep HEARTBEAT_INTERVAL_SECONDS
      now = Time.now.utc
      roster.workers.values.dup.each do |w|
        next if (now - w.last_heartbeat) <= DEADLINE_S

        jid = w.in_flight_job
        task = jid ? jobs_to_tasks.delete(jid) : nil
        dispatch(client, task: task, roster: roster, jobs_to_tasks: jobs_to_tasks) if task
        roster.workers.delete(w.worker_id)
        roster.by_role[w.role].delete(w.worker_id)
      end
    end
  end

  loop do
    env = client.receive_envelope
    break if env.nil?

    case env.type
    when 'job.heartbeat'
      roster.workers.each_value do |w|
        w.last_heartbeat = Time.now.utc if w.in_flight_job == env.job_id&.value
      end
    when 'job.completed', 'job.failed', 'job.cancelled'
      jobs_to_tasks.delete(env.job_id&.value)
      roster.workers.each_value do |w|
        w.in_flight_job = nil if w.in_flight_job == env.job_id&.value
      end
    end
  end
end

# Worker side ------------------------------------------------------------

def heartbeat_loop(client, job_id:, stop:)
  seq = 0
  until stop.set?
    env = Arcp::Envelope.build(
      type: 'job.heartbeat',
      job_id: job_id,
      payload: { sequence: seq, deadline_ms: HEARTBEAT_INTERVAL_SECONDS * 2000, state: 'running' },
      session_id: client.session_id
    )
    client.send_envelope(env)
    seq += 1
    stop.wait(HEARTBEAT_INTERVAL_SECONDS)
  end
end

Sync do
  supervisor = nil # ARCPClient(...) — privileged identity
  supervisor.open
  roster = Roster.new
  jobs_to_tasks = {}

  %w[indexer extractor archiver].each do |role|
    2.times do
      roster.add(Worker.new(worker_id: "#{role}-#{SecureRandom.hex(3)}",
                            role: role, last_heartbeat: Time.now.utc))
    end
  end

  Async { supervise(supervisor, roster, jobs_to_tasks) }

  6.times do |n|
    dispatch(
      supervisor,
      task: Task.new(
        task_id: format('t%03d', n),
        role: %w[indexer extractor archiver][n % 3],
        payload: { shard: n },
        idempotency_key: "openclaw:#{format('t%03d', n)}"
      ),
      roster: roster,
      jobs_to_tasks: jobs_to_tasks
    )
  end

  sleep 60
  supervisor.close
end
