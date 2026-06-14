# frozen_string_literal: true

module Arcp
  module Job
    # Acknowledgement payload for `job.subscribe` (spec §7.6). Carries the
    # attached job's current status, resolved agent, effective lease, and
    # correlation identifiers so a subscriber learns the job's state on
    # attach rather than only from subsequent events.
    Subscribed = Data.define(:job_id, :current_status, :agent, :lease,
                             :parent_job_id, :trace_id, :subscribed_from, :replayed) do
      def initialize(job_id:, subscribed_from:, current_status: nil, agent: nil,
                     lease: nil, parent_job_id: nil, trace_id: nil, replayed: false)
        super
      end

      def self.from_h(h)
        h = h.transform_keys(&:to_s)
        new(
          job_id: h.fetch('job_id'),
          current_status: h['current_status'],
          agent: h['agent'],
          lease: h['lease'] ? Arcp::Lease::Lease.from_h(h['lease']) : nil,
          parent_job_id: h['parent_job_id'],
          trace_id: h['trace_id'],
          subscribed_from: h.fetch('subscribed_from'),
          replayed: h.fetch('replayed', false)
        )
      end

      def to_h
        {
          'job_id' => job_id,
          'current_status' => current_status,
          'agent' => agent,
          'lease' => lease&.to_h,
          'parent_job_id' => parent_job_id,
          'trace_id' => trace_id,
          'subscribed_from' => subscribed_from,
          'replayed' => replayed
        }
      end
    end
  end
end
