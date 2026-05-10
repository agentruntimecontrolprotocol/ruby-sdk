# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Arcp::Extensions do
  describe '.namespaced?' do
    it 'accepts arcpx.<vendor>.<name>.v<n>' do
      expect(described_class.namespaced?('arcpx.example.workflow.v1')).to be(true)
      expect(described_class.namespaced?('arcpx.acme.cache-hit.v2')).to be(true)
    end

    it 'accepts reverse-DNS namespaces' do
      expect(described_class.namespaced?('com.acme.workflow.v2')).to be(true)
      expect(described_class.namespaced?('dev.example.thing.v1')).to be(true)
    end

    it 'rejects bare x- prefix' do
      expect(described_class.namespaced?('x-experimental')).to be(false)
    end

    it 'rejects core protocol types' do
      expect(described_class.namespaced?('session.open')).to be(false)
      expect(described_class.namespaced?('tool.invoke')).to be(false)
    end

    it 'rejects malformed namespaces' do
      expect(described_class.namespaced?('arcpx.example.workflow')).to be(false) # no .v<n>
      expect(described_class.namespaced?('arcpx.workflow.v1')).to be(false) # too few segments
      expect(described_class.namespaced?('Arcpx.Example.Workflow.v1')).to be(false)
      expect(described_class.namespaced?(nil)).to be(false)
    end
  end

  describe '.validate!' do
    it 'returns silently for valid namespaces' do
      expect { described_class.validate!('arcpx.acme.foo.v1') }.not_to raise_error
    end

    it 'raises on bare x- prefix' do
      expect { described_class.validate!('x-foo') }.to raise_error(Arcp::Error::InvalidArgument, /x- prefix/)
    end

    it 'raises on invalid namespaces' do
      expect { described_class.validate!('not.a.namespace') }.to raise_error(Arcp::Error::InvalidArgument)
    end
  end
end

RSpec.describe Arcp::ExtensionRegistry do
  it 'advertises only well-formed namespaces' do
    registry = described_class.new(advertised: ['arcpx.acme.foo.v1', 'com.example.bar.v1'])
    expect(registry.advertised).to contain_exactly('arcpx.acme.foo.v1', 'com.example.bar.v1')
  end

  it 'rejects malformed namespaces on construction' do
    expect { described_class.new(advertised: ['x-foo']) }.to raise_error(Arcp::Error::InvalidArgument)
  end

  it 'recognizes types under advertised namespaces' do
    registry = described_class.new(advertised: ['arcpx.acme.foo.v1'])
    expect(registry.supports?('arcpx.acme.foo.v1')).to be(true)
    expect(registry.supports?('arcpx.acme.foo.v1.subtype')).to be(true)
    expect(registry.supports?('arcpx.acme.bar.v1')).to be(false)
  end
end
