# frozen_string_literal: true

module Arcp
  module Job
    Cancel = Data.define(:job_id, :reason) do
      def self.from_h(h)
        h = h.transform_keys(&:to_s)
        new(job_id: h.fetch('job_id'), reason: h['reason'])
      end

      def to_h
        out = { 'job_id' => job_id }
        out['reason'] = reason if reason
        out
      end
    end
  end
end
