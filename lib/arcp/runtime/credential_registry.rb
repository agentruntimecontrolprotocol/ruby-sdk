# frozen_string_literal: true

require_relative '../clock'
require_relative '../credential'
require_relative '../credential_provisioner'

module Arcp
  module Runtime
    class CredentialRegistry
      def initialize(provisioner:, store:, clock: Arcp::SystemClock.new)
        @provisioner = provisioner
        @store = store
        @clock = clock
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
        revoke(credential_id)
        new_id = "#{credential_id}_rotated_#{@clock.now.to_i}"
        @store.record(job_id: job_id, credential_id: new_id)
        new_id
      end

      def revoke_all(job_id:)
        @store.outstanding(job_id: job_id).count do |credential_id|
          revoke(credential_id).tap do |revoked|
            @store.forget(job_id: job_id, credential_id: credential_id) if revoked
          end
        end
      end

      def reconcile_on_startup!
        @store.all_outstanding.each do |job_id, credential_ids|
          credential_ids.each do |credential_id|
            @store.forget(job_id: job_id, credential_id: credential_id) if revoke(credential_id)
          end
        end
        nil
      end

      private

      def revoke(credential_id)
        attempts = 0
        begin
          attempts += 1
          @provisioner.revoke(credential_id: credential_id)
          true
        rescue StandardError
          retry if attempts < 2

          false
        end
      end
    end
  end
end
