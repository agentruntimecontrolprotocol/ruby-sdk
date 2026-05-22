# frozen_string_literal: true

module Arcp
  module Job
    Handle = Data.define(:job_id, :agent, :submitted_at, :lease, :credentials) do
      def initialize(job_id:, agent:, submitted_at:, lease: nil, credentials: nil)
        super
      end

      def subscribe(client:, **kw) = client.subscribe_job(job_id: job_id, **kw)
      def cancel(client:, reason: nil) = client.cancel_job(job_id: job_id, reason: reason)
      def get_result(client:) = client.get_result(job_id: job_id)
      def credential_for(endpoint:) = Array(credentials).find { |credential| credential.endpoint == endpoint }
    end
  end
end
