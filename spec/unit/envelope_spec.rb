# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Arcp::Envelope do
  let(:base_kwargs) do
    {
      arcp: '1.0',
      id: Arcp::MessageId.new(value: 'msg_x'),
      type: 'job.progress',
      timestamp: Time.utc(2026, 5, 9, 13, 0, 0),
      payload: { percent: 42 }
    }
  end

  it 'requires the canonical fields' do
    expect { described_class.new(**base_kwargs) }.not_to raise_error
  end

  it 'rejects unknown priority values' do
    expect do
      described_class.new(**base_kwargs, priority: 'urgent')
    end.to raise_error(ArgumentError, /priority/)
  end

  it 'coerces string ids into typed ids' do
    env = described_class.new(**base_kwargs, session_id: 'sess_1', job_id: 'job_2')
    expect(env.session_id).to be_a(Arcp::SessionId).and have_attributes(value: 'sess_1')
    expect(env.job_id).to be_a(Arcp::JobId).and have_attributes(value: 'job_2')
  end

  it 'has structural equality' do
    a = described_class.new(**base_kwargs)
    b = described_class.new(**base_kwargs)
    expect(a).to eq(b)
    expect(a.hash).to eq(b.hash)
  end

  it 'is immutable' do
    env = described_class.new(**base_kwargs)
    expect(env).to be_frozen
    expect { env.instance_variable_set(:@type, 'mutated') }.to raise_error(FrozenError)
  end

  it 'supports pattern matching by attribute' do
    env = described_class.new(**base_kwargs)
    matched =
      case env
      in { type: 'job.progress', payload: { percent: Integer => percent } }
        percent
      end
    expect(matched).to eq(42)
  end

  describe '.build' do
    it 'fills in defaults' do
      env = described_class.build(type: 'log', payload: { level: 'info', message: 'hi' })
      expect(env.arcp).to eq('1.0')
      expect(env.id).to be_a(Arcp::MessageId)
      expect(env.timestamp).to be_within(2).of(Time.now.utc)
    end
  end

  describe '#to_wire_hash' do
    it 'omits nil-valued fields and the default normal priority' do
      env = described_class.new(**base_kwargs)
      hash = env.to_wire_hash
      expect(hash).not_to have_key(:source)
      expect(hash).not_to have_key(:priority)
      expect(hash[:type]).to eq('job.progress')
      expect(hash[:timestamp]).to eq('2026-05-09T13:00:00.000000Z')
      expect(hash[:payload]).to eq(percent: 42)
    end

    it 'preserves non-default priority' do
      env = described_class.new(**base_kwargs, priority: Arcp::Priority::CRITICAL)
      expect(env.to_wire_hash[:priority]).to eq('critical')
    end
  end
end

RSpec.describe Arcp::Json do
  let(:envelope) do
    Arcp::Envelope.new(
      arcp: '1.0',
      id: 'msg_1',
      type: 'job.progress',
      timestamp: Time.utc(2026, 5, 9, 13, 0, 0),
      session_id: 'sess_1',
      job_id: 'job_1',
      trace_id: 'trace_1',
      idempotency_key: 'idem-1',
      priority: 'high',
      payload: { percent: 11, message: 'hello' }
    )
  end

  it 'round-trips ids, type, timestamp, and payload' do
    decoded = described_class.decode_envelope(described_class.encode_envelope(envelope))
    expect(decoded.id.value).to eq(envelope.id.value)
    expect(decoded.type).to eq('job.progress')
    expect(decoded.session_id).to eq(envelope.session_id)
    expect(decoded.job_id).to eq(envelope.job_id)
    expect(decoded.timestamp.utc).to eq(envelope.timestamp.utc)
    expect(decoded.payload).to eq(percent: 11, message: 'hello')
  end

  it 'round-trips trace context, idempotency, and priority' do
    decoded = described_class.decode_envelope(described_class.encode_envelope(envelope))
    expect(decoded.trace_id).to eq(envelope.trace_id)
    expect(decoded.idempotency_key).to eq('idem-1')
    expect(decoded.priority).to eq('high')
  end

  it 'raises ParseError on invalid JSON' do
    expect { described_class.decode_envelope('{not json') }.to raise_error(Arcp::Error::ParseError)
  end

  it 'raises ParseError on missing required fields' do
    bad = '{"id":"x","type":"t","timestamp":"2026-05-09T13:00:00Z"}' # missing arcp
    expect { described_class.decode_envelope(bad) }.to raise_error(Arcp::Error::ParseError, /arcp/)
  end

  it 'raises ParseError on a malformed timestamp' do
    bad = '{"arcp":"1.0","id":"x","type":"t","timestamp":"yesterday"}'
    expect { described_class.decode_envelope(bad) }.to raise_error(Arcp::Error::ParseError)
  end
end
