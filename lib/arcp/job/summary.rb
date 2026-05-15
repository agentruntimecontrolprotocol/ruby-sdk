# frozen_string_literal: true

module Arcp
  module Job
    Summary = Data.define(:job_id, :agent, :status, :created_at, :lease_expires_at, :budget_remaining) do
      def self.from_h(h)
        h = h.transform_keys(&:to_s)
        new(
          job_id: h.fetch('job_id'),
          agent: h.fetch('agent'),
          status: h.fetch('status'),
          created_at: h['created_at'],
          lease_expires_at: h['lease_expires_at'],
          budget_remaining: h['budget_remaining']
        )
      end

      def to_h
        out = { 'job_id' => job_id, 'agent' => agent, 'status' => status }
        out['created_at']       = created_at if created_at
        out['lease_expires_at'] = lease_expires_at if lease_expires_at
        out['budget_remaining'] = budget_remaining if budget_remaining
        out
      end
    end
  end
end
