# frozen_string_literal: true

module Arcp
  module Job
    # Acknowledgement emitted by the runtime in response to `job.cancel`
    # for a non-terminal job (spec §7.4). It precedes the terminating
    # `job.error` whose code is `CANCELLED`.
    Cancelled = Data.define(:job_id, :reason) do
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
