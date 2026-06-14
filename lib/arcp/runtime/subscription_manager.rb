# frozen_string_literal: true

module Arcp
  module Runtime
    # Tracks per-job subscribers across sessions. Submitter session is
    # registered first; additional subscribers attach via `job.subscribe`
    # and receive a fan-out of every `job.event` and the terminating
    # `job.result` / `job.error`.
    class SubscriptionManager
      def initialize
        @subs = Hash.new { |h, k| h[k] = [] } # job_id => [[session_id, principal_id, queue], ...]
        @owners = {}                          # job_id => principal_id (submitter)
        @by_session = Hash.new { |h, k| h[k] = [] } # session_id => [job_id, ...]
        @mutex = Mutex.new
      end

      def register_owner(job_id, principal_id, session_id, queue)
        @mutex.synchronize do
          @owners[job_id] = principal_id
          @subs[job_id] << [session_id, principal_id, queue]
          @by_session[session_id] << job_id
        end
      end

      def attach(job_id, principal_id, session_id, queue)
        @mutex.synchronize do
          unless @owners[job_id] == principal_id
            raise Arcp::Errors::PermissionDenied.new(
              "principal not authorized to observe #{job_id}",
              details: { 'job_id' => job_id }
            )
          end

          @subs[job_id] << [session_id, principal_id, queue]
          @by_session[session_id] << job_id
        end
      end

      def detach(job_id, session_id)
        @mutex.synchronize do
          @subs[job_id].reject! { |s, _, _| s == session_id }
          forget_session_job(session_id, job_id)
        end
      end

      # Remove every subscription row owned by a session across all jobs.
      # Called when a session is torn down so fanout for still-running jobs
      # stops enqueueing into the closed session's orphaned outbox. Uses the
      # session index so cost is proportional to the session's own
      # subscriptions, not the whole runtime.
      def detach_session(session_id)
        @mutex.synchronize do
          job_ids = @by_session.delete(session_id) || []
          job_ids.uniq.each do |job_id|
            next unless @subs.key?(job_id)

            @subs[job_id].reject! { |s, _, _| s == session_id }
          end
        end
      end

      def fanout(job_id, envelope)
        targets = @mutex.synchronize { @subs[job_id].dup }
        targets.each { |_s, _p, q| q.enqueue(envelope) }
      end

      def owner_of(job_id) = @mutex.synchronize { @owners[job_id] }

      def clear(job_id)
        @mutex.synchronize do
          entries = @subs.delete(job_id) || []
          @owners.delete(job_id)
          entries.each { |s, _, _| forget_session_job(s, job_id) }
        end
      end

      # Replace the outbox bound to a session id across every job it
      # subscribes to. Used when a session resumes: the new actor's outbox
      # supersedes the old. Touches only the resumed session's subscriptions
      # via the session index, not every subscription in the runtime.
      def rebind_session(session_id, new_queue)
        @mutex.synchronize do
          (@by_session[session_id] || []).uniq.each do |job_id|
            next unless @subs.key?(job_id)

            @subs[job_id].each { |entry| entry[2] = new_queue if entry[0] == session_id }
          end
        end
      end

      private

      # Drop one occurrence of job_id from a session's index, removing the
      # session key entirely once it has no remaining subscriptions.
      def forget_session_job(session_id, job_id)
        list = @by_session[session_id]
        list.delete(job_id)
        @by_session.delete(session_id) if list.empty?
      end
    end
  end
end
