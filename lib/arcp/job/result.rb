# frozen_string_literal: true

module Arcp
  module Job
    Result = Data.define(:job_id, :final_status, :result, :result_id, :result_size, :completed_at) do
      def self.from_h(h)
        h = h.transform_keys(&:to_s)
        new(
          job_id: h.fetch('job_id'),
          final_status: h.fetch('final_status'),
          result: h['result'],
          result_id: h['result_id'],
          result_size: h['result_size'],
          completed_at: h['completed_at']
        )
      end

      def to_h
        out = { 'job_id' => job_id, 'final_status' => final_status }
        out['result']       = result if result
        out['result_id']    = result_id if result_id
        out['result_size']  = result_size if result_size
        out['completed_at'] = completed_at if completed_at
        out
      end

      def chunked? = !result_id.nil?
    end
  end
end
