# frozen_string_literal: true

require 'async'
require 'async/queue'
require 'digest'
require 'json'
require 'time'

module Arcp
  module Runtime
    AgentRegistration = Data.define(:name, :versions, :default, :handler)

    JobRecord = Data.define(:job_id, :agent, :principal_id, :status, :created_at,
                            :input, :submitter_session_id, :task, :seq) do
      def initialize(job_id:, agent:, principal_id:, status:, created_at:,
                     input:, submitter_session_id:, task:, seq: nil)
        super
      end

      def with(**kw) = self.class.new(**to_h, **kw)
    end

    # Owns agent registry + per-job lifecycle. Submitted jobs run as
    # child `Async::Task`s; cancellation propagates via `task.stop`.
    class JobManager
      attr_reader :runtime

      def initialize(runtime:, lease_manager:, subscription_manager:, event_log:, clock: Arcp::SystemClock.new)
        @runtime = runtime
        @leases = lease_manager
        @subs = subscription_manager
        @event_log = event_log
        @clock = clock
        @agents = {}                    # name => AgentRegistration
        @jobs = {}                      # job_id => JobRecord
        @order = []                     # insertion order of job_ids (oldest first)
        @next_seq = 0                   # monotonic counter assigned at submit
        @event_seq = Hash.new(0)        # submitter session_id => last emitted seq
        @idempotency = {}               # [principal, key] => job_id
        @accepted = {}                  # job_id => [resolved, lease, credentials, accepted_at]
        @mutex = Mutex.new
      end

      def register_agent(name:, versions:, default:, handler:)
        @mutex.synchronize do
          @agents[name] = AgentRegistration.new(
            name: name, versions: Array(versions).freeze,
            default: default, handler: handler
          )
        end
      end

      def agent_inventory
        @mutex.synchronize do
          Arcp::Session::AgentInventory.new(
            entries: @agents.values.map do |reg|
              Arcp::Session::AgentEntry.new(name: reg.name, versions: reg.versions, default: reg.default)
            end.freeze
          )
        end
      end

      def resolve_agent(ref_str)
        ref = Arcp::Job::AgentRef.parse(ref_str)
        reg = @mutex.synchronize { @agents[ref.name] }
        raise Arcp::Errors::AgentNotAvailable, "agent not registered: #{ref.name}" if reg.nil?

        version = ref.version || reg.default
        if version.nil? || (!reg.versions.empty? && !reg.versions.include?(version))
          raise Arcp::Errors::AgentVersionNotAvailable.new(
            "agent #{ref.name} has no version #{version.inspect}",
            details: { 'agent' => ref.name, 'version' => version, 'available' => reg.versions }
          )
        end

        [reg, "#{ref.name}@#{version}"]
      end

      def submit(submit:, principal_id:, session_id:, session_actor:)
        reg, resolved = resolve_agent(submit.agent)

        fingerprint = submit_fingerprint(submit, resolved) if submit.idempotency_key
        if submit.idempotency_key
          replay = idempotent_replay(submit.idempotency_key, principal_id, fingerprint)
          return replay if replay
        end

        job_id = Arcp::Ids.job_id

        lease = build_lease(submit, job_id)
        @leases.register(job_id, lease) if lease
        credentials = issue_credentials(
          job_id: job_id, lease: lease, agent: resolved, principal_id: principal_id
        )
        accepted_at = @clock.now.iso8601

        seq = @mutex.synchronize { @next_seq += 1 }
        # Record the job in `running` state up front so an agent task that
        # finishes before submit returns cannot have its terminal status
        # (`succeeded`/`error`) clobbered by a follow-up `running` assignment.
        record = JobRecord.new(
          job_id: job_id, agent: resolved, principal_id: principal_id,
          status: 'running', created_at: @clock.now.iso8601,
          input: submit.input, submitter_session_id: session_id, task: nil, seq: seq
        )
        @mutex.synchronize do
          @jobs[job_id] = record
          @order << job_id
          @accepted[job_id] = [resolved, lease, credentials, accepted_at]
          if submit.idempotency_key
            @idempotency[[principal_id, submit.idempotency_key]] = [job_id, fingerprint]
          end
        end

        @subs.register_owner(job_id, principal_id, session_id, session_actor.outbox)

        task = Async do |t|
          run_agent(t, reg, job_id, submit, lease)
        end
        @mutex.synchronize do
          existing = @jobs[job_id]
          @jobs[job_id] = existing.with(task: task) if existing
        end

        [job_id, resolved, lease, credentials, accepted_at]
      end

      TERMINAL_STATUSES = %w[success error cancelled timed_out].freeze

      def cancel(job_id:, principal_id:, reason: nil)
        record = @mutex.synchronize { @jobs[job_id] }
        raise Arcp::Errors::JobNotFound, "no such job: #{job_id}" unless record

        unless record.principal_id == principal_id
          raise Arcp::Errors::PermissionDenied.new(
            'only the submitting principal can cancel a job',
            details: { 'job_id' => job_id }
          )
        end

        # Spec §7.4: cancellation applies only to a non-terminal job. A
        # late/duplicate cancel must not overwrite a job's recorded terminal
        # status, double-emit a terminal job.error, or re-run teardown.
        return if TERMINAL_STATUSES.include?(record.status)

        record.task&.stop
        # Spec §7.4: acknowledge with job.cancelled *before* emitting the
        # terminating job.error(code=CANCELLED). publish_error clears the
        # subscriber set, so the acknowledgement must fan out first.
        publish_cancelled(job_id, reason)
        publish_error(job_id, Arcp::Job::JobError.new(
                                job_id: job_id, final_status: 'cancelled',
                                code: 'CANCELLED', message: reason, retryable: false, details: {}
                              ))
      end

      def publish_cancelled(job_id, reason)
        record = @mutex.synchronize { @jobs[job_id] }
        env = Arcp::Envelope.build(
          type: Arcp::MessageTypes::JOB_CANCELLED,
          session_id: record&.submitter_session_id || '',
          job_id: job_id,
          payload: Arcp::Job::Cancelled.new(job_id: job_id, reason: reason).to_h
        )
        @event_log.append(env.session_id, env)
        @subs.fanout(job_id, env)
        env
      end

      def list(principal_id:, filter: {}, limit: 50, cursor: nil)
        # Walk the insertion-ordered job index instead of re-sorting the
        # whole table per page. The cursor encodes the monotonic per-job
        # `seq` of the last row on the previous page (exclusive). A nil
        # or empty cursor starts from the oldest visible job.
        cursor_seq = decode_cursor(cursor)
        status_filter = filter['status']
        agent_filter = filter['agent']
        # Spec §6.6: created_after selects jobs created strictly after the
        # given UTC instant. Parsed once; an unparseable value disables the
        # filter rather than erroring the whole listing.
        created_after = parse_created_after(filter['created_after'])

        rows = []
        next_cursor = nil
        @mutex.synchronize do
          @order.each do |job_id|
            record = @jobs[job_id]
            next if record.nil?
            next if record.seq <= cursor_seq
            next if record.principal_id != principal_id
            next if status_filter && !status_filter.include?(record.status)
            next if agent_filter && !record.agent.start_with?(agent_filter)
            next if created_after && !record_created_after?(record, created_after)

            if rows.size == limit
              next_cursor = rows.last.seq.to_s
              break
            end
            rows << record
          end
        end

        summaries = rows.map do |r|
          lease = @leases.get(r.job_id)
          counter = @leases.counter(r.job_id)
          Arcp::Job::Summary.new(
            job_id: r.job_id, agent: r.agent, status: r.status, created_at: r.created_at,
            lease_expires_at: lease&.expires_at,
            budget_remaining: counter ? counter.snapshot.transform_values { |v| v.to_s('F') } : nil
          )
        end

        Arcp::Session::JobsResponse.new(
          jobs: summaries.map(&:to_h), next_cursor: next_cursor
        )
      end

      def decode_cursor(cursor)
        return 0 if cursor.nil? || cursor.to_s.empty?
        return cursor.to_i if /\A\d+\z/.match?(cursor.to_s)

        0
      end
      private :decode_cursor

      def parse_created_after(value)
        return nil if value.nil? || value.to_s.empty?

        Time.iso8601(value.to_s)
      rescue ArgumentError
        nil
      end
      private :parse_created_after

      def record_created_after?(record, threshold)
        Time.iso8601(record.created_at) > threshold
      rescue ArgumentError
        false
      end
      private :record_created_after?

      def lookup(job_id) = @mutex.synchronize { @jobs[job_id] }

      def publish_event(job_id, event)
        # Spec §8.3: event_seq is session-scoped, strictly monotonic, and
        # gap-free. Key the counter by the submitter session so every job in
        # a session shares one monotonic stream (two jobs no longer both
        # start at 1 and collide in that session's replay window).
        session_id, seq = @mutex.synchronize do
          sid = @jobs[job_id]&.submitter_session_id || ''
          [sid, @event_seq[sid] += 1]
        end
        env = Arcp::Envelope.build(
          type: Arcp::MessageTypes::JOB_EVENT,
          session_id: session_id,
          job_id: job_id, event_seq: seq, payload: event.to_h
        )
        @event_log.append(env.session_id, env)
        @subs.fanout(job_id, env)
        seq
      end

      def publish_result(job_id, result)
        record = @mutex.synchronize do
          # Spec §7.3: the terminal set is exactly success|error|cancelled|
          # timed_out. The listing status MUST be 'success' (matching the
          # job.result final_status), not 'succeeded'.
          @jobs[job_id] = @jobs[job_id].with(status: 'success') if @jobs[job_id]
          @jobs[job_id]
        end
        env = Arcp::Envelope.build(
          type: Arcp::MessageTypes::JOB_RESULT,
          session_id: record&.submitter_session_id || '',
          job_id: job_id, payload: result.to_h
        )
        @event_log.append(env.session_id, env)
        @subs.fanout(job_id, env)
        @subs.clear(job_id)
        @runtime.credential_registry&.revoke_all(job_id: job_id)
        @leases.revoke(job_id)
      end

      def publish_error(job_id, error)
        record = @mutex.synchronize do
          @jobs[job_id] = @jobs[job_id].with(status: error.final_status) if @jobs[job_id]
          @jobs[job_id]
        end
        env = Arcp::Envelope.build(
          type: Arcp::MessageTypes::JOB_ERROR,
          session_id: record&.submitter_session_id || '',
          job_id: job_id, payload: error.to_h
        )
        @event_log.append(env.session_id, env)
        @subs.fanout(job_id, env)
        @subs.clear(job_id)
        @runtime.credential_registry&.revoke_all(job_id: job_id)
        @leases.revoke(job_id)
      end

      private

      # Returns the replay value for an idempotent resubmission, or nil when
      # the key has not been seen. Raises DuplicateKey if the key was reused
      # with *any* conflicting parameter (agent, input, lease_request,
      # lease_constraints, max_runtime_sec), not just a different agent
      # (§7.2). A matching key returns the *same* job.accepted payload
      # (lease, credentials, accepted_at) recorded at first acceptance.
      def idempotent_replay(idempotency_key, principal_id, fingerprint)
        existing = @mutex.synchronize { @idempotency[[principal_id, idempotency_key]] }
        return nil unless existing

        existing_job_id, existing_fingerprint = existing
        if existing_fingerprint != fingerprint
          raise Arcp::Errors::DuplicateKey.new(
            'idempotency key reused with conflicting parameters',
            details: { 'job_id' => existing_job_id }
          )
        end

        cached = @mutex.synchronize { @accepted[existing_job_id] }
        cached ? [existing_job_id, *cached] : existing_job_id
      end

      # Stable digest of the parameters that define a job submission. Two
      # submissions with the same idempotency key must agree on all of these
      # to be treated as a replay rather than a conflict (§7.2).
      def submit_fingerprint(submit, resolved)
        canonical = {
          'agent' => resolved,
          'input' => submit.input,
          'lease_request' => submit.lease_request&.to_h,
          'lease_constraints' => submit.lease_constraints&.to_h,
          'max_runtime_sec' => submit.max_runtime_sec
        }
        Digest::SHA256.hexdigest(JSON.generate(deep_sort(canonical)))
      end

      def deep_sort(obj)
        case obj
        when Hash then obj.map { |k, v| [k.to_s, deep_sort(v)] }.sort_by(&:first).to_h
        when Array then obj.map { |v| deep_sort(v) }
        else obj
        end
      end

      def issue_credentials(job_id:, lease:, agent:, principal_id:)
        return nil unless @runtime.credential_registry

        @runtime.credential_registry.issue_for(
          job_id: job_id, lease: lease, agent: agent, principal_id: principal_id
        )
      end

      def build_lease(submit, job_id)
        request = submit.lease_request
        constraints = submit.lease_constraints
        # A constraints-only submit (e.g. just an expires_at) must still
        # produce a lease so the expiry is registered and enforceable.
        return nil unless request || constraints

        constraints&.enforce_max_budget!(request&.budget)

        Arcp::Lease::Lease.new(
          id: "lse_#{job_id}",
          capabilities: request&.capabilities || [],
          budget: request&.budget,
          model_use: request&.model_use,
          expires_at: constraints&.expires_at || request&.expires_at,
          issued_at: @clock.now.iso8601
        )
      end

      def run_agent(task, reg, job_id, submit, lease)
        ctx = JobContext.new(
          job_id: job_id, agent: reg.name, input: submit.input,
          lease: lease, sink: self, clock: @clock
        )
        watchdog = nil
        if submit.max_runtime_sec
          watchdog = task.async do
            task.sleep(submit.max_runtime_sec)
            # The handler may have finished (and finalized the context)
            # while we slept; do not raise a spurious "already finalized".
            next if ctx.done?

            ctx.fail!(code: 'TIMEOUT', message: 'max_runtime_sec elapsed', retryable: true,
                      final_status: 'timed_out')
          end
        end

        reg.handler.call(ctx)
        ctx.finish unless ctx.done?
      rescue Arcp::Error => e
        ctx&.fail!(code: e.code, message: e.message, retryable: e.retryable?, details: e.details || {})
      rescue Async::Stop
        nil
      rescue StandardError => e
        ctx&.fail!(code: 'INTERNAL_ERROR', message: e.message, retryable: true,
                   details: { 'class' => e.class.name })
      ensure
        # Cancel the watchdog so a completed job leaves no live timer fiber.
        watchdog&.stop
      end
    end
  end
end
