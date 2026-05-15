# frozen_string_literal: true

module Arcp
  module Job
    Accepted = Data.define(:job_id, :agent, :accepted_at, :lease) do
      def self.from_h(h)
        h = h.transform_keys(&:to_s)
        new(
          job_id: h.fetch('job_id'),
          agent: h.fetch('agent'),
          accepted_at: h['accepted_at'],
          lease: h['lease'] ? Arcp::Lease::Lease.from_h(h['lease']) : nil
        )
      end

      def to_h
        out = { 'job_id' => job_id, 'agent' => agent, 'accepted_at' => accepted_at }
        out['lease'] = lease.to_h if lease
        out
      end
    end
  end
end
