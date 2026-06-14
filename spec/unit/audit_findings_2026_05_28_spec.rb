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

  describe 'terminal/delegation timestamps derive from the injected clock (#59)' do
    let(:sink) do
      Class.new do
        attr_reader :result

        def runtime = nil
        def publish_event(_jid, _event) = 1
        def publish_result(_jid, result) = (@result = result)
        def publish_error(_jid, _err) = nil
      end.new
    end

    it 'JobContext#finish completed_at uses the clock, not Time.now' do
      clock = Arcp::FakeClock.new(now: Time.utc(2030, 4, 5, 6, 7, 8))
      ctx = Arcp::Runtime::JobContext.new(
        job_id: 'job_x', agent: 'a@1', input: nil, lease: nil, sink: sink, clock: clock
      )
      ctx.finish(result: 'ok')
      expect(sink.result.completed_at).to eq('2030-04-05T06:07:08Z')
    end

    it 'Subsetting.bound issued_at uses the clock, not Time.now' do
      clock = Arcp::FakeClock.new(now: Time.utc(2030, 4, 5, 6, 7, 8))
      parent = Arcp::Lease::Lease.new(
        id: 'lse_parent', capabilities: ['tool.call'], issued_at: '2026-01-01T00:00:00Z'
      )
      request = Arcp::Lease::LeaseRequest.new(capabilities: ['tool.call'])
      child = Arcp::Lease::Subsetting.bound(parent: parent, request: request, clock: clock)
      expect(child.issued_at).to eq('2030-04-05T06:07:08Z')
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
