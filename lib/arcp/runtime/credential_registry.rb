# frozen_string_literal: true

require 'logger'

require_relative '../clock'
require_relative '../credential'
require_relative '../credential_provisioner'

module Arcp
  module Runtime
    class CredentialRegistry
      # @param logger [Logger] sink for permanent revocation-failure records
      #   (spec §9.8.2/§14 require these to be logged).
      # @param on_revocation_failure [Proc, nil] optional operator hook invoked
      #   with `(credential_id:, job_id:, error:)` when a credential cannot be
      #   revoked after retries, so it can be surfaced (alert/metric/ticket).
      def initialize(provisioner:, store:, clock: Arcp::SystemClock.new,
                     logger: Logger.new($stderr), on_revocation_failure: nil)
        @provisioner = provisioner
        @store = store
        @clock = clock
        @logger = logger
        @on_revocation_failure = on_revocation_failure
        @mutex = Mutex.new
      end

      def issue_for(job_id:, lease:, agent:, principal_id:)
        credentials = @provisioner.issue(
          lease: lease, job_id: job_id, agent: agent, principal_id: principal_id
        )
        Array(credentials).each do |credential|
          @store.record(job_id: job_id, credential_id: credential.id)
        end
        Array(credentials).freeze
      end

      def rotate(job_id:, credential_id:, new_value:)
        revoke(credential_id, job_id: job_id)
        new_id = "#{credential_id}_rotated_#{@clock.now.to_i}"
        @store.record(job_id: job_id, credential_id: new_id)
        new_id
      end

      def revoke_all(job_id:)
        @store.outstanding(job_id: job_id).count do |credential_id|
          revoke(credential_id, job_id: job_id).tap do |revoked|
            @store.forget(job_id: job_id, credential_id: credential_id) if revoked
          end
        end
      end

      def reconcile_on_startup!
        @store.all_outstanding.each do |job_id, credential_ids|
          credential_ids.each do |credential_id|
            next unless revoke(credential_id, job_id: job_id)

            @store.forget(job_id: job_id, credential_id: credential_id)
          end
        end
        nil
      end

      private

      # Best-effort revocation with one retry (spec §9.8.2). A credential that
      # cannot be revoked after retries leaves spending authority dangling, so
      # the permanent failure MUST be logged (§9.8.2/§14) and is surfaced via
      # the operator hook. The credential id is left outstanding in the store
      # so it can be retried on a later sweep / restart.
      def revoke(credential_id, job_id: nil)
        attempts = 0
        begin
          attempts += 1
          @provisioner.revoke(credential_id: credential_id)
          true
        rescue StandardError => e
          retry if attempts < 2

          record_permanent_failure(credential_id, job_id, e)
          false
        end
      end

      def record_permanent_failure(credential_id, job_id, error)
        @logger&.error(
          'ARCP: permanent credential revocation failure ' \
          "job_id=#{job_id.inspect} credential_id=#{credential_id.inspect} " \
          "error=#{error.class}: #{error.message}"
        )
        @on_revocation_failure&.call(credential_id: credential_id, job_id: job_id, error: error)
      end
    end
  end
end
