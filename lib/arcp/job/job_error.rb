# frozen_string_literal: true

module Arcp
  module Job
    JobError = Data.define(:job_id, :final_status, :code, :message, :retryable, :details) do
      def self.from_h(h)
        h = h.transform_keys(&:to_s)
        new(
          job_id: h.fetch('job_id'),
          final_status: h.fetch('final_status'),
          code: h.fetch('code'),
          message: h['message'],
          retryable: h.fetch('retryable', false),
          details: h['details'] || {}
        )
      end

      def to_h
        out = { 'job_id' => job_id, 'final_status' => final_status,
                'code' => code, 'retryable' => retryable }
        out['message'] = message if message
        out['details'] = details unless details.empty?
        out
      end

      def to_exception
        Arcp::Errors.for(code, message: message, details: details, retryable: retryable)
      end
    end
  end
end
