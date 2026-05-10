# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Arcp do
  it 'declares a protocol version' do
    expect(Arcp::PROTOCOL_VERSION).to eq('1.0')
  end

  it 'declares an implementation version' do
    expect(Arcp::IMPL_VERSION).to eq('0.1.0')
  end
end
