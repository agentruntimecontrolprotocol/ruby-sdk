# frozen_string_literal: true

require_relative 'credential'
require_relative 'errors'

module Arcp
  module CredentialProvisioner
    def issue(lease:, job_id:, agent:, principal_id:)
      raise NotImplementedError
    end

    def revoke(credential_id:)
      raise NotImplementedError
    end
  end

  module Credentials
    BUDGET_EXHAUSTED_CODES = %w[BUDGET_EXHAUSTED budget_exhausted insufficient_quota].freeze

    def self.translate_upstream_error(error)
      return error unless budget_exhausted?(error)

      Arcp::Errors::BudgetExhausted.new(
        error.message,
        details: { 'upstream_class' => error.class.name }
      )
    end

    def self.budget_exhausted?(error)
      code = error.respond_to?(:code) ? error.code.to_s : nil
      status = error.respond_to?(:status) ? error.status.to_i : nil
      BUDGET_EXHAUSTED_CODES.include?(code) || status == 402
    end

    class InMemoryProvisioner
      include Arcp::CredentialProvisioner

      attr_reader :issued, :revoked

      def initialize(endpoint: 'https://gateway.test/v1', profile: 'openai')
        @endpoint = endpoint
        @profile = profile
        @issued = []
        @revoked = []
      end

      def issue(lease:, job_id:, agent:, principal_id:)
        credential = Arcp::Credential.new(
          id: "cred_#{job_id}_0",
          scheme: Arcp::Credential::SCHEME_BEARER,
          value: "sk-test-#{job_id}",
          endpoint: @endpoint,
          profile: @profile,
          constraints: constraints_for(lease)
        )
        @issued << {
          credential: credential,
          job_id: job_id,
          agent: agent,
          principal_id: principal_id
        }
        [credential]
      end

      def revoke(credential_id:)
        @revoked << credential_id
        nil
      end

      private

      def constraints_for(lease)
        return {} unless lease

        {
          'cost.budget' => lease.budget&.to_a,
          'model.use' => lease.model_use,
          'expires_at' => lease.expires_at
        }.compact
      end
    end

    class CredentialStore
      def record(job_id:, credential_id:)
        raise NotImplementedError
      end

      def forget(job_id:, credential_id:)
        raise NotImplementedError
      end

      def outstanding(job_id:)
        raise NotImplementedError
      end

      def all_outstanding
        raise NotImplementedError
      end
    end

    class InMemoryStore < CredentialStore
      def initialize
        super
        @by_job = Hash.new { |hash, key| hash[key] = [] }
        @mutex = Mutex.new
      end

      def record(job_id:, credential_id:)
        @mutex.synchronize { @by_job[job_id] |= [credential_id] }
        nil
      end

      def forget(job_id:, credential_id:)
        @mutex.synchronize do
          @by_job[job_id].delete(credential_id)
          @by_job.delete(job_id) if @by_job[job_id].empty?
        end
        nil
      end

      def outstanding(job_id:)
        @mutex.synchronize { @by_job[job_id].dup.freeze }
      end

      def all_outstanding
        @mutex.synchronize do
          @by_job.transform_values { |ids| ids.dup.freeze }.freeze
        end
      end
    end
  end
end
