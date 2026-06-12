# frozen_string_literal: true

require 'spec_helper'
require 'base64'
require 'bigdecimal'

RSpec.describe 'audit findings 2026-06-11 (unit)' do
  describe 'BudgetCounter rejects negative decrements (#67)' do
    subject(:counter) do
      Arcp::Lease::BudgetCounter.new(initial: { 'USD' => BigDecimal('1.00') })
    end

    it 'returns false and leaves the balance unchanged for a negative amount' do
      expect(counter.try_decrement('USD', BigDecimal('-5'))).to be(false)
      expect(counter.get('USD')).to eq(BigDecimal('1.00'))
    end

    it 'still decrements a valid positive amount' do
      expect(counter.try_decrement('USD', BigDecimal('0.25'))).to be(true)
      expect(counter.get('USD')).to eq(BigDecimal('0.75'))
    end
  end

  describe 'LeaseManager#try_spend! rejects negative amounts (#67)' do
    let(:manager) { Arcp::Runtime::LeaseManager.new }
    let(:lease) do
      Arcp::Lease::Lease.new(
        id: 'lse_job1', capabilities: ['cost.spend'],
        budget: Arcp::Lease::CostBudget.parse(['USD:1.00']),
        issued_at: Time.now.utc.iso8601
      )
    end

    before { manager.register('job1', lease) }

    it 'does not credit the counter and raises InvalidRequest (not a misleading exhausted error)' do
      expect do
        manager.try_spend!('job1', 'USD', BigDecimal('-5'))
      end.to raise_error(Arcp::Errors::InvalidRequest)
      expect(manager.remaining('job1')['USD']).to eq(BigDecimal('1.00'))
    end
  end
end
