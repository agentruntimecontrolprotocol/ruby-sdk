# frozen_string_literal: true

require 'spec_helper'
require 'async'
require 'base64'

RSpec.describe 'artifacts', :integration do
  let(:bearer) { Arcp::Auth::Bearer.new(tokens: { 'tok-alice' => 'alice@example.com' }) }
  let(:client_identity) { { 'kind' => 'rspec', 'version' => '1.0', 'fingerprint' => 'sha256:test' } }

  it 'puts and fetches an artifact, then refuses fetch after release' do
    Sync do
      client_side, runtime_side = Arcp::Transport::Memory.pair
      runtime = Arcp::Runtime::Runtime.new(schemes: [bearer])
      Async { runtime.serve(runtime_side) }
      client = Arcp::Client::Client.new(transport: client_side)
      client.open(auth: { scheme: 'bearer', token: 'tok-alice' }, client: client_identity)

      bytes = '{"hello":"world"}'
      put = Arcp::Envelope.build(
        type: 'artifact.put',
        payload: Arcp::Messages::Artifacts::ArtifactPut.new(
          artifact_id: 'art_test', media_type: 'application/json',
          size: bytes.bytesize, data: Base64.strict_encode64(bytes),
          sha256: nil, expires_at: nil
        ),
        session_id: client.session_id
      )
      client_side.send_envelope(put)
      put_response = client_side.receive_envelope
      expect(put_response.payload).to be_a(Arcp::Messages::Artifacts::ArtifactRef)

      fetch = Arcp::Envelope.build(
        type: 'artifact.fetch',
        payload: Arcp::Messages::Artifacts::ArtifactFetch.new(
          artifact_id: 'art_test', redirect_ok: true
        ),
        session_id: client.session_id
      )
      client_side.send_envelope(fetch)
      fetch_response = client_side.receive_envelope
      expect(fetch_response.payload).to be_a(Arcp::Messages::Artifacts::ArtifactRef)
      decoded = Base64.strict_decode64(fetch_response.payload.data)
      expect(decoded).to eq(bytes)

      release = Arcp::Envelope.build(
        type: 'artifact.release',
        payload: Arcp::Messages::Artifacts::ArtifactRelease.new(artifact_id: 'art_test'),
        session_id: client.session_id
      )
      client_side.send_envelope(release)
      release_response = client_side.receive_envelope
      expect(release_response.payload).to be_a(Arcp::Messages::Control::Ack)

      client_side.send_envelope(fetch)
      after_release = client_side.receive_envelope
      expect(after_release.payload).to be_a(Arcp::Messages::Control::Nack)
      expect(after_release.payload.code).to eq(Arcp::ErrorCode::NOT_FOUND)
      client.close
    end
  end
end

RSpec.describe Arcp::Runtime::ArtifactStore do
  let(:fake_clock) do
    klass = Class.new do
      class << self
        attr_accessor :now_value
      end

      def self.now
        now_value
      end
    end
    klass.now_value = Time.utc(2026, 5, 9, 12, 0, 0)
    klass
  end

  it 'sweeps expired artifacts' do
    store = described_class.new(clock: fake_clock, default_retention_seconds: 30)
    store.put(
      session_id: Arcp::SessionId.new(value: 'sess_x'),
      artifact_id: Arcp::ArtifactId.new(value: 'art_a'),
      media_type: 'application/octet-stream',
      data: Base64.strict_encode64('hello')
    )
    fake_clock.now_value = fake_clock.now_value + 60
    expect(store.sweep_expired).to eq(1)
    expect(store.size).to eq(0)
  end

  it 'rejects mismatched sha256' do
    store = described_class.new(clock: fake_clock)
    expect do
      store.put(
        session_id: Arcp::SessionId.new(value: 'sess_x'),
        artifact_id: Arcp::ArtifactId.new(value: 'art_a'),
        media_type: 'application/octet-stream',
        data: Base64.strict_encode64('hello'),
        sha256: 'deadbeef' * 8
      )
    end.to raise_error(Arcp::Error::InvalidArgument, /sha256/)
  end
end
