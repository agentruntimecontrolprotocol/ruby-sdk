# frozen_string_literal: true

require 'spec_helper'
require 'arcp/store/event_log'

RSpec.describe Arcp::Store::EventLog do
  let(:log) { described_class.new(path: ':memory:') }

  after { log.close }

  def envelope(id:, **overrides)
    Arcp::Envelope.new(
      arcp: '1.0',
      id: id,
      type: 'log',
      timestamp: Time.utc(2026, 5, 9, 12, 0, 0),
      payload: { level: 'info', message: id },
      **overrides
    )
  end

  it 'appends and assigns monotonic sequence numbers' do
    a = log.append(envelope(id: 'msg_a'))
    b = log.append(envelope(id: 'msg_b'))
    c = log.append(envelope(id: 'msg_c'))
    expect([a, b, c]).to eq([1, 2, 3])
    expect(log.size).to eq(3)
  end

  it 'is idempotent on duplicate message ids' do
    first = log.append(envelope(id: 'msg_dup'))
    second = log.append(envelope(id: 'msg_dup'))
    expect(first).to eq(second)
    expect(log.size).to eq(1)
  end

  it 'replays in monotonic order with optional after_seq' do
    log.append(envelope(id: 'msg_1'))
    log.append(envelope(id: 'msg_2'))
    log.append(envelope(id: 'msg_3'))

    all = log.replay
    expect(all.map { |e| e.id.value }).to eq(%w[msg_1 msg_2 msg_3])

    after_one = log.replay(after_seq: 1)
    expect(after_one.map { |e| e.id.value }).to eq(%w[msg_2 msg_3])
  end

  it 'looks up monotonic seq for a known id' do
    log.append(envelope(id: 'msg_x'))
    log.append(envelope(id: 'msg_y'))
    expect(log.seq_for('msg_x')).to eq(1)
    expect(log.seq_for(Arcp::MessageId.new(value: 'msg_y'))).to eq(2)
    expect(log.seq_for('missing')).to be_nil
  end

  it 'filters replay by session/job/stream/trace/types' do
    log.append(envelope(id: 'msg_1', session_id: 'sess_a', job_id: 'job_1'))
    log.append(envelope(id: 'msg_2', session_id: 'sess_a', job_id: 'job_2'))
    log.append(envelope(id: 'msg_3', session_id: 'sess_b'))

    by_session = log.replay(session_id: 'sess_a')
    expect(by_session.map { |e| e.id.value }).to eq(%w[msg_1 msg_2])

    by_job = log.replay(job_id: 'job_2')
    expect(by_job.map { |e| e.id.value }).to eq(%w[msg_2])

    by_type = log.replay(types: ['metric'])
    expect(by_type).to be_empty
  end

  it 'sweeps expired events outside retention' do
    fake_now = Time.utc(2026, 5, 9, 12, 0, 0)
    fake = Class.new do
      class << self
        attr_accessor :current
      end

      def self.now
        current
      end
    end
    fake.current = fake_now
    short_log = described_class.new(path: ':memory:', retention_seconds: 1, clock: fake)
    short_log.append(envelope(id: 'msg_old'))
    fake.current = fake_now + 5
    short_log.append(envelope(id: 'msg_new'))
    deleted = short_log.sweep_expired
    expect(deleted).to eq(1)
    remaining = short_log.replay.map { |e| e.id.value }
    expect(remaining).to eq(%w[msg_new])
    short_log.close
  end

  describe 'idempotent outcome storage' do
    it 'records and looks up outcomes by (principal, key)' do
      newly = log.record_idempotent_outcome(
        session_principal: 'alice@example.com',
        idempotency_key: 'refund-1',
        outcome: { status: 'ok', amount: 100 }
      )
      expect(newly).to be(true)
      again = log.record_idempotent_outcome(
        session_principal: 'alice@example.com',
        idempotency_key: 'refund-1',
        outcome: { status: 'changed' }
      )
      expect(again).to be(false)
      stored = log.lookup_idempotent_outcome(session_principal: 'alice@example.com', idempotency_key: 'refund-1')
      expect(stored).to eq(status: 'ok', amount: 100)
    end
  end
end
