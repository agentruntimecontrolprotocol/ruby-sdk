# frozen_string_literal: true

require 'spec_helper'
require 'async'

RSpec.describe 'streaming', :integration do
  let(:bearer) { Arcp::Auth::Bearer.new(tokens: { 'tok-alice' => 'alice@example.com' }) }
  let(:client_identity) { { 'kind' => 'rspec', 'version' => '1.0', 'fingerprint' => 'sha256:test' } }

  it 'emits stream.open, ordered chunks, and stream.close from a tool' do
    Sync do
      client_side, runtime_side = Arcp::Transport::Memory.pair
      runtime = Arcp::Runtime::Runtime.new(schemes: [bearer])
      runtime.register_tool('echo-stream') do |ctx, args|
        stream_id = ctx.streams.open(session_id: ctx.session_id, kind: 'text', content_type: 'text/plain')
        Array(args[:words] || %w[hello world]).each do |w|
          ctx.streams.chunk(stream_id, content: w)
        end
        ctx.streams.close(stream_id, reason: 'eos')
        :ok
      end
      Async { runtime.serve(runtime_side) }
      client = Arcp::Client::Client.new(transport: client_side)
      client.open(auth: { scheme: 'bearer', token: 'tok-alice' }, client: client_identity)

      result = client.invoke(tool: 'echo-stream', arguments: { words: %w[a b c] })
      expect(result).to be_successful
      stream_events = result.events.select { |e| e.payload.is_a?(Arcp::Messages::Streaming::StreamChunk) }
      expect(stream_events.map { |e| e.payload.content }).to eq(%w[a b c])
      expect(stream_events.map { |e| e.payload.sequence }).to eq([1, 2, 3])

      open_event = result.events.find { |e| e.payload.is_a?(Arcp::Messages::Streaming::StreamOpen) }
      close_event = result.events.find { |e| e.payload.is_a?(Arcp::Messages::Streaming::StreamClose) }
      expect(open_event).not_to be_nil
      expect(close_event).not_to be_nil
      client.close
    end
  end
end

RSpec.describe Arcp::Runtime::StreamManager do
  it 'rejects unknown stream kinds' do
    sm = described_class.new(emit: ->(_, _) {})
    expect do
      sm.open(session_id: Arcp::SessionId.random, kind: 'mystery')
    end.to raise_error(Arcp::Error::InvalidArgument, /mystery/)
  end

  it 'increments sequence numbers monotonically' do
    emitted = []
    sm = described_class.new(emit: ->(record, payload) { emitted << [record.stream_id.value, payload] })
    sid = sm.open(session_id: Arcp::SessionId.random, kind: 'text')
    sm.chunk(sid, content: 'a')
    sm.chunk(sid, content: 'b')
    sm.chunk(sid, content: 'c')
    sm.close(sid, reason: 'done')

    chunk_payloads = emitted.map { |_, p| p }.grep(Arcp::Messages::Streaming::StreamChunk)
    expect(chunk_payloads.map(&:sequence)).to eq([1, 2, 3])
    expect(chunk_payloads.map(&:content)).to eq(%w[a b c])
  end

  it 'refuses to chunk after close' do
    sm = described_class.new(emit: ->(_, _) {})
    sid = sm.open(session_id: Arcp::SessionId.random, kind: 'text')
    sm.close(sid)
    expect { sm.chunk(sid, content: 'x') }.to raise_error(Arcp::Error::FailedPrecondition)
  end

  it 'emits stream.error with code on error()' do
    emitted = []
    sm = described_class.new(emit: ->(_, p) { emitted << p })
    sid = sm.open(session_id: Arcp::SessionId.random, kind: 'text')
    sm.error(sid, code: Arcp::ErrorCode::CANCELLED, message: 'cancelled')
    err = emitted.find { |p| p.is_a?(Arcp::Messages::Streaming::StreamError) }
    expect(err.code).to eq(Arcp::ErrorCode::CANCELLED)
  end
end
