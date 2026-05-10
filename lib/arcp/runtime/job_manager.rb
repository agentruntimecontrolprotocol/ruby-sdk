# frozen_string_literal: true

require 'async'

require 'arcp/error'
require 'arcp/error_code'
require 'arcp/ids'
require 'arcp/messages/control'
require 'arcp/messages/execution'

module Arcp
  module Runtime
    # State machine constants for jobs (§10.2).
    module JobState
      ACCEPTED  = :accepted
      QUEUED    = :queued
      RUNNING   = :running
      BLOCKED   = :blocked
      PAUSED    = :paused
      COMPLETED = :completed
      FAILED    = :failed
      CANCELLED = :cancelled

      TERMINAL = [COMPLETED, FAILED, CANCELLED].freeze
      ALL      = [ACCEPTED, QUEUED, RUNNING, BLOCKED, PAUSED, COMPLETED, FAILED, CANCELLED].freeze

      ALLOWED_TRANSITIONS = {
        ACCEPTED => [QUEUED, RUNNING, CANCELLED, FAILED].freeze,
        QUEUED => [RUNNING, CANCELLED, FAILED].freeze,
        RUNNING => [BLOCKED, PAUSED, COMPLETED, FAILED, CANCELLED].freeze,
        BLOCKED => [RUNNING, CANCELLED, FAILED].freeze,
        PAUSED => [RUNNING, CANCELLED, FAILED].freeze,
        COMPLETED => [].freeze,
        FAILED => [].freeze,
        CANCELLED => [].freeze
      }.freeze
    end

    # Per-job mutable record managed by the JobManager.
    class JobRecord
      attr_reader :job_id, :session_id, :tool, :arguments, :state,
                  :sequence, :last_heartbeat_at, :cancellation_deadline,
                  :correlation_id, :trace_id

      def initialize(job_id:, session_id:, tool:, arguments:, clock:,
                     correlation_id: nil, trace_id: nil)
        @job_id = job_id
        @session_id = session_id
        @tool = tool
        @arguments = arguments
        @clock = clock
        @correlation_id = correlation_id
        @trace_id = trace_id
        @state = JobState::ACCEPTED
        @sequence = 0
        @last_heartbeat_at = clock.now
        @cancellation_deadline = nil
      end

      def transition!(target)
        unless JobState::ALLOWED_TRANSITIONS.fetch(@state).include?(target)
          raise Arcp::Error::FailedPrecondition,
                "illegal transition #{@state} -> #{target} for job #{@job_id}"
        end
        @state = target
      end

      def terminal?
        JobState::TERMINAL.include?(@state)
      end

      def next_sequence!
        @sequence += 1
      end

      def record_heartbeat!
        @last_heartbeat_at = @clock.now
      end

      def request_cancellation!(deadline_seconds)
        @cancellation_deadline = @clock.now + deadline_seconds
      end
    end

    # Manages job lifecycle, heartbeats, and cancellation.
    #
    # The JobManager is fiber-aware: each `start` spawns a child task
    # of the parent task. `cancel!` cooperatively terminates within a
    # deadline before escalating to `task.stop`.
    class JobManager
      DEFAULT_HEARTBEAT_INTERVAL_SECONDS = 30
      DEFAULT_HEARTBEAT_MISSES_BEFORE_FAIL = 2

      attr_reader :records, :cancel_reason

      # @param clock [#now]
      # @param heartbeat_interval_seconds [Numeric]
      # @param heartbeat_recovery [String] 'fail' or 'block'
      # @param emit [#call] called with each emitted payload
      def initialize(emit:, clock: Time, heartbeat_interval_seconds: DEFAULT_HEARTBEAT_INTERVAL_SECONDS,
                     heartbeat_recovery: 'fail')
        @clock = clock
        @heartbeat_interval_seconds = heartbeat_interval_seconds
        @heartbeat_recovery = heartbeat_recovery
        @emit = emit
        @records = {}
        @tasks = {}
        @mutex = Mutex.new
      end

      # Accept a job for execution; return its id.
      #
      # @param session_id [Arcp::SessionId]
      # @param tool [String]
      # @param arguments [Hash]
      # @return [Arcp::JobId]
      def accept(session_id:, tool:, arguments:, correlation_id: nil, trace_id: nil)
        job_id = JobId.random
        record = JobRecord.new(
          job_id: job_id, session_id: session_id,
          tool: tool, arguments: arguments, clock: @clock,
          correlation_id: correlation_id, trace_id: trace_id
        )
        @mutex.synchronize { @records[job_id.value] = record }
        @emit.call(record, Messages::Execution::JobAccepted.new(detail: nil))
        job_id
      end

      # Start a job under a parent task. Yields a `JobContext` to the
      # block; the block's return value becomes the `tool.result.value`.
      #
      # @param parent_task [Async::Task]
      # @param job_id [Arcp::JobId]
      # @param extras [Hash] additional fields (e.g. stream_manager) to
      #   attach to the JobContext
      # @yieldparam ctx [Arcp::Runtime::JobContext]
      # @return [Async::Task]
      def start(parent_task, job_id, extras: {}, &)
        record = lookup!(job_id)
        record.transition!(JobState::RUNNING)
        @emit.call(record, Messages::Execution::JobStarted.new(detail: nil))

        task = parent_task.async do |child|
          ctx = JobContext.new(record: record, manager: self, task: child, extras: extras)
          execute_job(ctx, record, &)
        end
        @mutex.synchronize { @tasks[job_id.value] = task }
        task
      end

      # Emit a heartbeat for the job.
      def heartbeat(job_id)
        record = lookup!(job_id)
        record.record_heartbeat!
        seq = record.next_sequence!
        @emit.call(record, Messages::Execution::JobHeartbeat.new(
                             sequence: seq,
                             deadline_ms: @heartbeat_interval_seconds * 2 * 1000,
                             state: record.state.to_s
                           ))
      end

      # Emit progress.
      def progress(job_id, percent: nil, message: nil, detail: nil)
        record = lookup!(job_id)
        @emit.call(record, Messages::Execution::JobProgress.new(
                             percent: percent, message: message, detail: detail
                           ))
      end

      # Cancel a job cooperatively. The job's task is given `deadline_ms`
      # to exit on its own; otherwise it is force-stopped.
      #
      # @param job_id [Arcp::JobId]
      # @param reason [String]
      # @param deadline_ms [Numeric]
      def cancel!(job_id, reason: nil, deadline_ms: 5_000)
        record = lookup(job_id)
        return false if record.nil? || record.terminal?

        record.request_cancellation!(deadline_ms / 1000.0)
        @emit.call(record, Messages::Control::CancelAccepted.new(target: 'job', target_id: job_id.value))
        task = @mutex.synchronize { @tasks[job_id.value] }
        # Stop the task; `Async::Stop` is raised inside it, which the
        # `execute_job` rescue clause turns into `:cancelled`. The
        # deadline applies to cooperative cleanup before the stop, but
        # for v0.1 we drive it via task.stop directly.
        @cancel_reason = reason
        task&.stop
        true
      end

      # Mark a job blocked (e.g. on human input or interrupt).
      def block(job_id)
        record = lookup!(job_id)
        record.transition!(JobState::BLOCKED) unless record.state == JobState::BLOCKED
      end

      # Mark a blocked job runnable again.
      def unblock(job_id)
        record = lookup!(job_id)
        record.transition!(JobState::RUNNING) if record.state == JobState::BLOCKED
      end

      # Complete a job with a value.
      def complete(job_id, value: nil, result_ref: nil)
        record = lookup!(job_id)
        return if record.terminal?

        record.transition!(JobState::COMPLETED)
        @emit.call(record, Messages::Execution::JobCompleted.new(value: value, result_ref: result_ref))
      end

      # Fail a job with a structured error.
      def fail_job(job_id, code:, message:, retryable: false, details: nil)
        record = lookup!(job_id)
        return if record.terminal?

        record.transition!(JobState::FAILED)
        @emit.call(record, Messages::Execution::JobFailed.new(
                             code: code, message: message, retryable: retryable, details: details
                           ))
      end

      # Cancel terminal — used internally after cooperative cancel.
      def finalize_cancellation(job_id, reason:)
        record = lookup!(job_id)
        return if record.terminal?

        record.transition!(JobState::CANCELLED)
        @emit.call(record, Messages::Execution::JobCancelled.new(reason: reason, code: ErrorCode::CANCELLED))
      end

      # @api private
      def lookup(job_id)
        key = job_id.respond_to?(:value) ? job_id.value : job_id
        @mutex.synchronize { @records[key] }
      end

      # @api private
      def lookup!(job_id)
        record = lookup(job_id)
        raise Arcp::Error::NotFound, "job not found: #{job_id}" if record.nil?

        record
      end

      private

      def execute_job(ctx, record)
        value = yield(ctx)
        complete(record.job_id, value: value)
      rescue Async::Stop
        finalize_cancellation(record.job_id, reason: @cancel_reason || 'stopped')
      rescue Arcp::Error => e
        fail_job(record.job_id, code: e.code, message: e.message, retryable: e.retryable?, details: e.details)
      rescue StandardError => e
        fail_job(record.job_id, code: ErrorCode::INTERNAL, message: e.message)
      end
    end

    # Per-job context handed to the worker block.
    class JobContext
      attr_reader :record, :task, :extras

      def initialize(record:, manager:, task:, extras: {})
        @record = record
        @manager = manager
        @task = task
        @extras = extras
      end

      def job_id         = @record.job_id
      def session_id     = @record.session_id
      def progress(**kw) = @manager.progress(@record.job_id, **kw)
      def heartbeat      = @manager.heartbeat(@record.job_id)

      # @return [Arcp::Runtime::StreamManager, nil]
      def streams = @extras[:streams]

      # @return [Arcp::Runtime::PendingRegistry, nil]
      def pending = @extras[:pending]
    end
  end
end
