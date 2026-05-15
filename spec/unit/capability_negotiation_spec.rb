# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Arcp::Session::CapabilitySet do
  it 'intersects feature lists' do
    local = described_class.new(features: %w[heartbeat ack subscribe], encodings: %w[utf8 base64], agents: nil)
    remote = described_class.new(features: %w[heartbeat subscribe progress], encodings: %w[utf8], agents: nil)
    effective = local.intersect(remote)
    expect(effective.features).to eq(%w[heartbeat subscribe])
    expect(effective.encodings).to eq(%w[utf8])
  end

  it 'reports support per feature' do
    caps = described_class.local(features: %w[heartbeat ack], agents: nil)
    expect(caps.supports?('heartbeat')).to be(true)
    expect(caps.supports?('list_jobs')).to be(false)
  end

  it 'serializes to wire shape' do
    caps = described_class.local(features: ['heartbeat'], encodings: ['utf8'])
    expect(caps.to_h).to eq('features' => ['heartbeat'], 'encodings' => ['utf8'])
  end
end

RSpec.describe Arcp::Session::AgentInventory do
  let(:inv) do
    described_class.from_array([
                                 { 'name' => 'code-refactor', 'versions' => %w[1.0.0 2.0.0], 'default' => '2.0.0' },
                                 { 'name' => 'test-runner' }
                               ])
  end

  it 'resolves bare names to defaults' do
    expect(inv.resolve('code-refactor')).to eq('code-refactor@2.0.0')
  end

  it 'resolves pinned versions' do
    expect(inv.resolve('code-refactor@1.0.0')).to eq('code-refactor@1.0.0')
  end

  it 'returns nil for unknown agent or version' do
    expect(inv.resolve('code-refactor@9.9.9')).to be_nil
    expect(inv.resolve('nope')).to be_nil
  end

  it 'lists versions per agent' do
    expect(inv.versions_for('code-refactor')).to eq(%w[1.0.0 2.0.0])
    expect(inv.versions_for('test-runner')).to eq([])
  end
end
