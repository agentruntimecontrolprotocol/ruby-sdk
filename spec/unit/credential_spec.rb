# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Arcp::Credential do
  it 'round-trips the provisioned credential wire shape' do
    credential = described_class.from_h(
      'id' => 'cred_1',
      'scheme' => 'bearer',
      'value' => 'sk-test',
      'endpoint' => 'https://gateway.test/v1',
      'profile' => 'openai',
      'constraints' => { 'model.use' => ['tier-fast/*'] }
    )

    expect(credential.to_h).to include(
      'id' => 'cred_1',
      'value' => 'sk-test',
      'constraints' => { 'model.use' => ['tier-fast/*'] }
    )
  end

  it 'redacts credential values for non-wire surfaces' do
    credential = described_class.new(
      id: 'cred_1',
      scheme: 'bearer',
      value: 'sk-test',
      endpoint: 'https://gateway.test/v1'
    )

    expect(credential.to_redacted_h['value']).to eq('[REDACTED]')
  end
end

RSpec.describe Arcp::ModelPattern do
  it 'matches model globs' do
    expect(described_class.match?(['tier-fast/*'], 'tier-fast/gpt-4o')).to be(true)
    expect(described_class.match?(['anthropic/claude-3-haiku-*'], 'anthropic/claude-3-opus')).to be(false)
    expect(described_class.match?(nil, 'tier-fast/gpt-4o')).to be(false)
  end

  it 'allows child literals under a parent model glob' do
    expect(described_class.implied_by?(['tier-fast/*'], 'tier-fast/gpt-4o')).to be(true)
    expect(described_class.implied_by?(['tier-fast/*'], 'anthropic/claude-3-opus')).to be(false)
  end
end
