# frozen_string_literal: true

module Arcp
  module Runtime
    # Tracks per-job subscribers across sessions. Submitter session is
    # registered first; additional subscribers attach via `job.subscribe`
    # and receive a fan-out of every `job.event` and the terminating
    # `job.result` / `job.error`.
    class SubscriptionManager
      def initialize
        @subs = Hash.new { |h, k| h[k] = [] } # job_id => [[session_id, principal_id, queue], …]
        @owners = {}                          # job_id => principal_id (submitter)
        @mutex = Mutex.new
      end

      def register_owner(job_id, principal_id, session_id, queue)
        @mutex.synchronize do
          @owners[job_id] = principal_id
          @subs[job_id] << [session_id, principal_id, queue]
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
        end
      end

      def detach(job_id, session_id)
        @mutex.synchronize do
          @subs[job_id].reject! { |s, _, _| s == session_id }
        end
      end

      def fanout(job_id, envelope)
        targets = @mutex.synchronize { @subs[job_id].dup }
        targets.each { |_s, _p, q| q.enqueue(envelope) }
      end

      def owner_of(job_id) = @mutex.synchronize { @owners[job_id] }

      def clear(job_id)
        @mutex.synchronize do
          @subs.delete(job_id)
          @owners.delete(job_id)
        end
      end
    end
  end
end
