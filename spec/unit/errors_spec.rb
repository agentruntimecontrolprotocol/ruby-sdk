# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Arcp::Errors do
  it 'exposes 18 wire codes (15 protocol + 3 v1.1 extras + library-internal)' do
    expect(Arcp::Errors::WIRE_CODES).to include(
      'CANCELLED', 'INVALID_REQUEST', 'UNAUTHENTICATED', 'PERMISSION_DENIED',
      'JOB_NOT_FOUND', 'AGENT_NOT_AVAILABLE', 'DUPLICATE_KEY', 'RATE_LIMITED',
      'INTERNAL_ERROR', 'HEARTBEAT_LOST', 'BACKPRESSURE', 'PROTOCOL_VIOLATION',
      'AGENT_VERSION_NOT_AVAILABLE', 'LEASE_EXPIRED', 'BUDGET_EXHAUSTED'
    )
  end

  it 'looks up classes by code' do
    klass = described_class::BY_CODE.fetch('LEASE_EXPIRED')
    expect(klass).to eq(described_class::LeaseExpired)
  end

  it 'builds typed errors from a wire payload' do
    err = described_class.for('BUDGET_EXHAUSTED', message: 'spent', details: { 'currency' => 'USD' })
    expect(err).to be_a(described_class::BudgetExhausted)
    expect(err.code).to eq('BUDGET_EXHAUSTED')
    expect(err.retryable?).to be(false)
    expect(err.details).to eq('currency' => 'USD')
  end

  it 'falls back to Internal for unknown codes' do
    err = described_class.for('SOMETHING_NEW')
    expect(err).to be_a(described_class::Internal)
  end

  it 'partitions retryable codes' do
    expect(described_class::RETRYABLE_BY_DEFAULT).to include('RATE_LIMITED', 'HEARTBEAT_LOST', 'BACKPRESSURE')
    expect(described_class::NON_RETRYABLE_BY_DEFAULT).to include(
      'PERMISSION_DENIED', 'LEASE_EXPIRED', 'BUDGET_EXHAUSTED', 'AGENT_VERSION_NOT_AVAILABLE'
    )
  end
end
