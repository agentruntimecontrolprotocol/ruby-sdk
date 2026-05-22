# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Arcp::Runtime::CredentialRegistry do
  it 'records issued credential ids in the store' do
    provisioner = Arcp::Credentials::InMemoryProvisioner.new
    store = Arcp::Credentials::InMemoryStore.new
    registry = described_class.new(provisioner: provisioner, store: store)

    credentials = registry.issue_for(job_id: 'job_1', lease: nil, agent: 'echo', principal_id: 'alice')

    expect(credentials.first.id).to eq('cred_job_1_0')
    expect(store.outstanding(job_id: 'job_1')).to eq(['cred_job_1_0'])
  end

  it 'maps upstream budget exhaustion to the ARCP budget error' do
    stub_const('UpstreamBudgetError', upstream_budget_error_class)
    error = UpstreamBudgetError.new('gateway budget exhausted')

    translated = Arcp::Credentials.translate_upstream_error(error)

    expect(translated).to be_a(Arcp::Errors::BudgetExhausted)
    expect(translated.details['upstream_class']).to include('UpstreamBudgetError')
  end

  it 'revokes all outstanding credentials and forgets successful revocations' do
    provisioner = Arcp::Credentials::InMemoryProvisioner.new
    store = Arcp::Credentials::InMemoryStore.new
    registry = described_class.new(provisioner: provisioner, store: store)

    registry.issue_for(job_id: 'job_1', lease: nil, agent: 'echo', principal_id: 'alice')

    expect(registry.revoke_all(job_id: 'job_1')).to eq(1)
    expect(provisioner.revoked).to eq(['cred_job_1_0'])
    expect(store.outstanding(job_id: 'job_1')).to be_empty
  end

  it 'retries transient revoke failures once' do
    provisioner = flaky_provisioner_class.new
    store = Arcp::Credentials::InMemoryStore.new
    store.record(job_id: 'job_1', credential_id: 'cred_1')
    registry = described_class.new(provisioner: provisioner, store: store)

    expect(registry.revoke_all(job_id: 'job_1')).to eq(1)
    expect(provisioner.revoked).to eq(['cred_1'])
    expect(store.outstanding(job_id: 'job_1')).to be_empty
  end

  it 'reconciles outstanding credentials on startup' do
    provisioner = Arcp::Credentials::InMemoryProvisioner.new
    store = Arcp::Credentials::InMemoryStore.new
    store.record(job_id: 'job_1', credential_id: 'cred_1')

    described_class.new(provisioner: provisioner, store: store).reconcile_on_startup!

    expect(provisioner.revoked).to eq(['cred_1'])
    expect(store.all_outstanding).to be_empty
  end

  def flaky_provisioner_class
    Class.new do
      include Arcp::CredentialProvisioner

      attr_reader :revoked

      def initialize
        self.attempts = Hash.new(0)
        self.revoked = []
      end

      def issue(lease:, job_id:, agent:, principal_id:)
        []
      end

      def revoke(credential_id:)
        attempts[credential_id] += 1
        raise 'transient' if attempts[credential_id] == 1

        revoked << credential_id
      end

      private

      attr_accessor :attempts
      attr_writer :revoked
    end
  end

  def upstream_budget_error_class
    Class.new(StandardError) do
      def code = 'budget_exhausted'
    end
  end
end
