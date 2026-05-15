# frozen_string_literal: true

require 'async'
require 'async/queue'
require 'time'

module Arcp
  module Runtime
    AgentRegistration = Data.define(:name, :versions, :default, :handler)

    JobRecord = Data.define(:job_id, :agent, :principal_id, :status, :created_at,
                            :input, :submitter_session_id, :task) do
      def with(**kw) = self.class.new(**to_h.merge(kw))
    end

    # Owns agent registry + per-job lifecycle. Submitted jobs run as
    # child `Async::Task`s; cancellation propagates via `task.stop`.
    class JobManager
      def initialize(runtime:, lease_manager:, subscription_manager:, event_log:, clock: Arcp::SystemClock.new)
        @runtime = runtime
        @leases = lease_manager
        @subs = subscription_manager
        @event_log = event_log
        @clock = clock
        @agents = {}                    # name => AgentRegistration
        @jobs = {}                      # job_id => JobRecord
        @event_seq = Hash.new(0)        # job_id => last emitted seq
        @idempotency = {}               # [principal, key] => job_id
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

        if submit.idempotency_key
          key = [principal_id, submit.idempotency_key]
          if (existing = @mutex.synchronize { @idempotency[key] })
            existing_record = @mutex.synchronize { @jobs[existing] }
            if existing_record && existing_record.agent != resolved
              raise Arcp::Errors::DuplicateKey.new(
                'idempotency key reused with different agent',
                details: { 'job_id' => existing }
              )
            end
            return existing
          end
        end

        job_id = Arcp::Ids.job_id

        lease = build_lease(submit, job_id)
        @leases.register(job_id, lease) if lease

        record = JobRecord.new(
          job_id: job_id, agent: resolved, principal_id: principal_id,
          status: 'pending', created_at: @clock.now.iso8601,
          input: submit.input, submitter_session_id: session_id, task: nil
        )
        @mutex.synchronize do
          @jobs[job_id] = record
          @idempotency[[principal_id, submit.idempotency_key]] = job_id if submit.idempotency_key
        end

        @subs.register_owner(job_id, principal_id, session_id, session_actor.outbox)

        task = Async do |t|
          run_agent(t, reg, job_id, submit, lease)
        end
        @mutex.synchronize { @jobs[job_id] = @jobs[job_id].with(task: task, status: 'running') }

        [job_id, resolved, lease]
      end

      def cancel(job_id:, principal_id:, reason: nil)
        record = @mutex.synchronize { @jobs[job_id] }
        raise Arcp::Errors::JobNotFound, "no such job: #{job_id}" unless record

        unless record.principal_id == principal_id
          raise Arcp::Errors::PermissionDenied.new(
            'only the submitting principal can cancel a job',
            details: { 'job_id' => job_id }
          )
        end

        record.task&.stop
        publish_error(job_id, Arcp::Job::JobError.new(
                                job_id: job_id, final_status: 'cancelled',
                                code: 'CANCELLED', message: reason, retryable: false, details: {}
                              ))
      end

      def list(principal_id:, filter: {}, limit: 50, cursor: nil)
        offset = cursor ? cursor.to_i : 0
        rows = @mutex.synchronize do
          @jobs.values
               .select { |r| r.principal_id == principal_id }
               .select { |r| filter['status'].nil? || filter['status'].include?(r.status) }
               .select { |r| filter['agent'].nil? || r.agent.start_with?(filter['agent']) }
               .sort_by(&:created_at)
        end

        page = rows[offset, limit] || []
        next_cursor = ((offset + page.size) < rows.size) ? (offset + page.size).to_s : nil

        summaries = page.map do |r|
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

      def lookup(job_id) = @mutex.synchronize { @jobs[job_id] }

      def publish_event(job_id, event)
        seq = @mutex.synchronize { @event_seq[job_id] += 1 }
        env = Arcp::Envelope.build(
          type: Arcp::MessageTypes::JOB_EVENT,
          session_id: @mutex.synchronize { @jobs[job_id]&.submitter_session_id || '' },
          job_id: job_id, event_seq: seq, payload: event.to_h
        )
        @event_log.append(env.session_id, env)
        @subs.fanout(job_id, env)
        seq
      end

      def publish_result(job_id, result)
        record = @mutex.synchronize { @jobs[job_id] = @jobs[job_id].with(status: 'succeeded') if @jobs[job_id]; @jobs[job_id] }
        env = Arcp::Envelope.build(
          type: Arcp::MessageTypes::JOB_RESULT,
          session_id: record&.submitter_session_id || '',
          job_id: job_id, payload: result.to_h
        )
        @event_log.append(env.session_id, env)
        @subs.fanout(job_id, env)
        @subs.clear(job_id)
        @leases.revoke(job_id)
      end

      def publish_error(job_id, error)
        record = @mutex.synchronize { @jobs[job_id] = @jobs[job_id].with(status: error.final_status) if @jobs[job_id]; @jobs[job_id] }
        env = Arcp::Envelope.build(
          type: Arcp::MessageTypes::JOB_ERROR,
          session_id: record&.submitter_session_id || '',
          job_id: job_id, payload: error.to_h
        )
        @event_log.append(env.session_id, env)
        @subs.fanout(job_id, env)
        @subs.clear(job_id)
        @leases.revoke(job_id)
      end

      private

      def build_lease(submit, job_id)
        return nil unless submit.lease_request

        Arcp::Lease::Lease.new(
          id: "lse_#{job_id}",
          capabilities: submit.lease_request.capabilities,
          budget: submit.lease_request.budget,
          expires_at: submit.lease_constraints&.expires_at || submit.lease_request.expires_at,
          issued_at: @clock.now.iso8601
        )
      end

      def run_agent(task, reg, job_id, submit, lease)
        ctx = JobContext.new(
          job_id: job_id, agent: reg.name, input: submit.input,
          lease: lease, sink: self
        )
        if submit.max_runtime_sec
          deadline = task.async do
            task.sleep(submit.max_runtime_sec)
            ctx.fail!(code: 'TIMEOUT', message: 'max_runtime_sec elapsed', retryable: true)
            task.stop
          end
        end

        reg.handler.call(ctx)
        ctx.finish unless ctx.instance_variable_get(:@done)
      rescue Arcp::Error => e
        ctx&.fail!(code: e.code, message: e.message, retryable: e.retryable?, details: e.details || {})
      rescue Async::Stop
        nil
      rescue StandardError => e
        ctx&.fail!(code: 'INTERNAL_ERROR', message: e.message, retryable: true,
                   details: { 'class' => e.class.name })
      end
    end
  end
end
