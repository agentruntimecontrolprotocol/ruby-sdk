# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Arcp::IdBuilder do
  describe Arcp::SessionId do
    it 'generates random ids with the right prefix' do
      id = described_class.random
      expect(id.value).to start_with('sess_')
      expect(id.value.size).to be >= 30
    end

    it 'rejects empty values' do
      expect { described_class.new(value: '') }.to raise_error(ArgumentError)
      expect { described_class.new(value: '   ') }.to raise_error(ArgumentError)
    end

    it 'rejects non-string values' do
      expect { described_class.new(value: 123) }.to raise_error(ArgumentError)
    end

    it 'is immutable' do
      id = described_class.new(value: 'sess_x')
      expect(id).to be_frozen
      expect { id.instance_variable_set(:@value, 'other') }.to raise_error(FrozenError)
    end

    it 'serializes to JSON as a string' do
      id = described_class.new(value: 'sess_x')
      expect(id.to_json).to eq('"sess_x"')
    end
  end

  it 'distinguishes id types from one another' do
    sess = Arcp::SessionId.new(value: 'shared')
    msg  = Arcp::MessageId.new(value: 'shared')
    expect(sess).not_to eq(msg)
    expect(sess.is_a?(Arcp::MessageId)).to be(false)
    expect(msg.is_a?(Arcp::SessionId)).to be(false)
  end

  it 'pattern-matches by class' do
    id = Arcp::JobId.new(value: 'job_a')
    matched =
      case id
      in Arcp::SessionId then :session
      in Arcp::JobId then :job
      else :other
      end
    expect(matched).to eq(:job)
  end

  it 'declares all expected id types' do
    %i[
      SessionId MessageId JobId StreamId SubscriptionId
      ArtifactId LeaseId TraceId SpanId
    ].each do |sym|
      expect(Arcp.const_defined?(sym)).to be(true), "missing #{sym}"
    end
  end
end
