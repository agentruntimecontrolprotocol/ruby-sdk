# frozen_string_literal: true

require 'spec_helper'
require 'bigdecimal'

RSpec.describe 'audit findings 2026-05-28 (unit)' do
  describe 'CapabilitySet advertises [json] encodings (#54)' do
    it 'defaults session encodings to ["json"], not result_chunk data encodings' do
      caps = Arcp::Session::CapabilitySet.local
      expect(caps.encodings).to eq(%w[json])
    end

    it 'intersects non-empty with a spec-conformant ["json"] peer' do
      local = Arcp::Session::CapabilitySet.local
      peer = Arcp::Session::CapabilitySet.local(encodings: %w[json])
      expect(local.intersect(peer).encodings).to eq(%w[json])
    end
  end

  describe 'Progress rejects a negative current (#55)' do
    it 'raises INVALID_REQUEST when current is negative' do
      expect do
        Arcp::Job::EventBody::Progress.new(current: -1)
      end.to raise_error(Arcp::Errors::InvalidRequest)
    end

    it 'raises INVALID_REQUEST when from_h carries a negative current' do
      expect do
        Arcp::Job::EventBody::Progress.from_h('current' => -3, 'total' => 10)
      end.to raise_error(Arcp::Errors::InvalidRequest)
    end

    it 'accepts a non-negative current' do
      body = Arcp::Job::EventBody::Progress.new(current: 0, total: 10)
      expect(body.current).to eq(0)
    end
  end
end
