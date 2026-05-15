# frozen_string_literal: true

module Arcp
  module Job
    Handle = Data.define(:job_id, :agent, :submitted_at, :lease) do
      def subscribe(client:, **kw) = client.subscribe_job(job_id: job_id, **kw)
      def cancel(client:, reason: nil) = client.cancel_job(job_id: job_id, reason: reason)
      def get_result(client:) = client.get_result(job_id: job_id)
    end
  end
end
