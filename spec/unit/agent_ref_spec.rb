# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Arcp::Job::AgentRef do
  it 'parses bare names' do
    ref = described_class.parse('echo')
    expect(ref.name).to eq('echo')
    expect(ref.version).to be_nil
    expect(ref.to_s).to eq('echo')
  end

  it 'parses name@version' do
    ref = described_class.parse('code-refactor@1.0.0')
    expect(ref.name).to eq('code-refactor')
    expect(ref.version).to eq('1.0.0')
    expect(ref.to_s).to eq('code-refactor@1.0.0')
  end
end
