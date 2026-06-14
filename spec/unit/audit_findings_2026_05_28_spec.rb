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

  describe 'SubscriptionManager.rebind_session only touches the resumed session (#63)' do
    subject(:manager) { Arcp::Runtime::SubscriptionManager.new }

    before do
      50.times { |i| manager.register_owner("job#{i}", "p#{i}", "sess#{i}", "q#{i}") }
      manager.register_owner('jobA', 'pT', 'S', 'old')
      manager.register_owner('jobB', 'pT', 'S', 'old')
    end

    def queues_for(job_id)
      manager.instance_variable_get(:@subs)[job_id].map { |(_s, _p, q)| q }
    end

    it 'rewrites only the resumed session\'s entries via the session index' do
      manager.rebind_session('S', 'new')

      expect(queues_for('jobA')).to eq(['new'])
      expect(queues_for('jobB')).to eq(['new'])
      expect(queues_for('job0')).to eq(['q0']) # unrelated session untouched
      expect(queues_for('job49')).to eq(['q49'])
      expect(manager.instance_variable_get(:@by_session)['S']).to eq(%w[jobA jobB])
    end

    it 'keeps the session index consistent across detach and clear' do
      manager.detach('jobA', 'S')
      expect(manager.instance_variable_get(:@by_session)['S']).to eq(['jobB'])

      manager.clear('jobB')
      expect(manager.instance_variable_get(:@by_session)).not_to have_key('S')
    end
  end

  describe 'EventLog evicts by time without relying on session.ack (#58)' do
    def env(seq)
      Arcp::Envelope.build(type: 'job.event', session_id: 's', job_id: 'j', event_seq: seq, payload: {})
    end

    it 'drops events older than the resume window on the next append' do
      clock = Arcp::FakeClock.new
      log = Arcp::Runtime::EventLog.new(window_sec: 10, clock: clock)

      log.append('s', env(1))
      expect(log.buffer_size('s')).to eq(1)

      clock.advance(11)
      log.append('s', env(2))

      expect(log.replay('s').map(&:event_seq)).to eq([2])
      expect(log.job_buffer_size('j')).to eq(1)
    end

    it 'expire! reclaims idle buffers between writes' do
      clock = Arcp::FakeClock.new
      log = Arcp::Runtime::EventLog.new(window_sec: 10, clock: clock)
      log.append('s', env(1))

      clock.advance(11)
      log.expire!

      expect(log.buffer_size('s')).to eq(0)
    end
  end

  describe 'streamed result chunks are size-capped (#56)' do
    let(:sink) do
      Class.new do
        def runtime = nil
        def publish_event(_jid, _event) = 1
        def publish_result(_jid, _result) = nil
        def publish_error(_jid, _err) = nil
      end.new
    end

    def ctx_with_sink
      Arcp::Runtime::JobContext.new(
        job_id: 'job_cap', agent: 'a@1', input: nil, lease: nil, sink: sink
      )
    end

    it 'raises INTERNAL_ERROR when a single chunk exceeds the per-chunk cap' do
      writer = ctx_with_sink.stream_result(max_chunk_bytes: 8)
      expect { writer.write('x' * 9, more: false) }.to raise_error(Arcp::Errors::Internal)
    end

    it 'raises INTERNAL_ERROR when the cumulative total exceeds the total cap' do
      writer = ctx_with_sink.stream_result(max_chunk_bytes: 100, max_total_bytes: 10)
      writer.write('x' * 6, more: true)
      expect { writer.write('y' * 6, more: false) }.to raise_error(Arcp::Errors::Internal)
    end

    it 'allows writes within the caps' do
      writer = ctx_with_sink.stream_result(max_chunk_bytes: 100, max_total_bytes: 100)
      expect { writer.write('hello', more: false) }.not_to raise_error
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
