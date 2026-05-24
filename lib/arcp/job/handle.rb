# frozen_string_literal: true

module Arcp
  module Job
    # Lightweight client-side handle for a submitted job.
    Handle = Data.define(:job_id, :agent, :submitted_at, :lease, :credentials) do
      # Builds a handle value object.
      def initialize(job_id:, agent:, submitted_at:, lease: nil, credentials: nil)
        super
      end

      # Subscribes to this job using the given client.
      def subscribe(client:, **kw) = client.subscribe_job(job_id: job_id, **kw)
      # Cancels this job using the given client.
      def cancel(client:, reason: nil) = client.cancel_job(job_id: job_id, reason: reason)
      # Fetches the terminal result for this job using the given client.
      def get_result(client:) = client.get_result(job_id: job_id)
      # Returns the provisioned credential for the given endpoint, if any.
      def credential_for(endpoint:) = Array(credentials).find { |credential| credential.endpoint == endpoint }
    end
  end
end
