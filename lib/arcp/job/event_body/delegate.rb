# frozen_string_literal: true

module Arcp
  module Job
    module EventBody
      Delegate = Data.define(:child_job_id, :agent, :lease) do
        def self.from_h(h)
          h = h.transform_keys(&:to_s)
          new(
            child_job_id: h.fetch('child_job_id'),
            agent: h.fetch('agent'),
            lease: h['lease'] ? Arcp::Lease::Lease.from_h(h['lease']) : nil
          )
        end

        def to_h
          out = { 'child_job_id' => child_job_id, 'agent' => agent }
          out['lease'] = lease.to_h if lease
          out
        end
      end
    end
  end
end
