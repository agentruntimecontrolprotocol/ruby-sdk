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

  describe 'JobError#to_exception preserves the wire retryable flag (#68)' do
    def job_error(code:, retryable:)
      Arcp::Job::JobError.from_h(
        'job_id' => 'job1', 'final_status' => 'error',
        'code' => code, 'retryable' => retryable
      )
    end

    it 'honors a non-retryable wire flag over the class default' do
      exc = job_error(code: 'TIMEOUT', retryable: false).to_exception
      expect(exc).to be_a(Arcp::Errors::Timeout)
      expect(exc.retryable?).to be(false)
    end

    it 'honors a retryable wire flag over the class default' do
      exc = job_error(code: 'LEASE_EXPIRED', retryable: true).to_exception
      expect(exc).to be_a(Arcp::Errors::LeaseExpired)
      expect(exc.retryable?).to be(true)
    end

    it 'keeps LEASE_EXPIRED / BUDGET_EXHAUSTED non-retryable when the wire agrees' do
      expect(job_error(code: 'LEASE_EXPIRED', retryable: false).to_exception.retryable?).to be(false)
      expect(job_error(code: 'BUDGET_EXHAUSTED', retryable: false).to_exception.retryable?).to be(false)
    end
  end

  describe 'SubscriptionManager#detach_session (#73)' do
    let(:manager) { Arcp::Runtime::SubscriptionManager.new }
    let(:recording_queue) do
      Class.new do
        attr_reader :items

        def initialize = @items = []
        def enqueue(item) = @items << item
      end
    end

    it 'removes every subscription row for a session so fanout skips its outbox' do
      owner_q = recording_queue.new
      observer_q = recording_queue.new
      manager.register_owner('job1', 'alice', 'ses_owner', owner_q)
      manager.attach('job1', 'alice', 'ses_obs', observer_q)

      manager.detach_session('ses_owner')
      manager.fanout('job1', :event)

      expect(owner_q.items).to be_empty
      expect(observer_q.items).to eq([:event])
    end
  end

  describe 'ResultChunk#decoded uses strict base64 (#77)' do
    def chunk(data)
      Arcp::Job::EventBody::ResultChunk.new(
        result_id: 'res_1', chunk_seq: 0, data: data, encoding: 'base64', more: false
      )
    end

    it 'round-trips binary data byte-for-byte' do
      binary = (0..255).to_a.pack('C*')
      encoded = Base64.strict_encode64(binary)
      expect(chunk(encoded).decoded).to eq(binary)
    end

    it 'raises InvalidRequest on malformed (line-wrapped/whitespace) base64' do
      wrapped = "#{Base64.strict_encode64('hello world payload')}\n"
      expect { chunk(wrapped).decoded }.to raise_error(Arcp::Errors::InvalidRequest)
    end
  end

  describe 'EventLog#replay_job boundary helper (#75)' do
    it 'excludes the event equal to the strict from_event_seq cursor' do
      clock = Arcp::FakeClock.new
      log = Arcp::Runtime::EventLog.new(window_sec: 60, clock: clock)
      3.times do |i|
        log.append('ses_1', Arcp::Envelope.build(
                              type: Arcp::MessageTypes::JOB_EVENT,
                              session_id: 'ses_1', job_id: 'job1', event_seq: i + 1,
                              payload: { 'kind' => 'log' }
                            ))
      end

      # Mirrors the session actor passing from_event_seq + 1.
      replay = log.replay_job('job1', from_event_seq: 1 + 1)
      expect(replay.map(&:event_seq)).to eq([2, 3])
    end
  end
end
