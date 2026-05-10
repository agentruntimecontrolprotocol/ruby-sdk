# frozen_string_literal: true

require 'spec_helper'
require 'async'

RSpec.describe 'session handshake', :integration do
  let(:bearer) { Arcp::Auth::Bearer.new(tokens: { 'tok-alice' => 'alice@example.com' }) }
  let(:client_identity) { { 'kind' => 'rspec', 'version' => '1.0', 'fingerprint' => 'sha256:test' } }

  def serve_runtime(transport, **runtime_kwargs)
    runtime = Arcp::Runtime::Runtime.new(**runtime_kwargs)
    [runtime, Async { runtime.serve(transport) }]
  end

  def with_pair(**runtime_kwargs)
    Sync do
      client_side, runtime_side = Arcp::Transport::Memory.pair
      _runtime, server_task = serve_runtime(runtime_side, **runtime_kwargs)
      client = Arcp::Client::Client.new(transport: client_side)
      begin
        yield client
      ensure
        client.close
        server_task.wait
      end
    end
  end

  it 'authenticates with bearer and returns negotiated capabilities' do
    with_pair(schemes: [bearer]) do |client|
      result = client.open(
        auth: { scheme: 'bearer', token: 'tok-alice' },
        client: client_identity,
        capabilities: { streaming: true, human_input: true }
      )
      expect(result[:session_id]).to be_a(Arcp::SessionId)
      expect(result[:runtime][:kind]).to eq('arcp-ruby')
      expect(result[:capabilities][:streaming]).to be(true)
      expect(result[:capabilities][:durable_jobs]).to be(false) # client did not advertise
    end
  end

  it 'rejects unknown bearer tokens with UNAUTHENTICATED' do
    with_pair(schemes: [bearer]) do |client|
      expect do
        client.open(
          auth: { scheme: 'bearer', token: 'tok-bogus' },
          client: client_identity
        )
      end.to raise_error(Arcp::Error::Unauthenticated, /not recognized/)
    end
  end

  it 'rejects unimplemented schemes with UNIMPLEMENTED' do
    with_pair(schemes: [bearer]) do |client|
      expect do
        client.open(
          auth: { scheme: 'mtls' },
          client: client_identity
        )
      end.to raise_error(Arcp::Error::Unimplemented, /mtls/)
    end
  end

  it 'rejects none scheme without anonymous capability' do
    with_pair(schemes: [bearer]) do |client|
      expect do
        client.open(
          auth: { scheme: 'none' },
          client: client_identity,
          capabilities: { anonymous: true }
        )
      end.to raise_error(Arcp::Error::Unauthenticated, /anonymous/)
    end
  end

  it 'accepts none scheme when both sides advertise anonymous' do
    runtime_caps = Arcp::Runtime::Runtime::DEFAULT_CAPABILITIES.merge(anonymous: true)
    with_pair(schemes: [bearer], capabilities: runtime_caps) do |client|
      result = client.open(
        auth: { scheme: 'none' },
        client: client_identity,
        capabilities: { anonymous: true }
      )
      expect(result[:capabilities][:anonymous]).to be(true)
    end
  end

  it 'authenticates with signed_jwt' do
    secret = 'super-secret'
    payload = { 'sub' => 'jwt-user', 'aud' => 'arcp-runtime', 'iat' => Time.now.to_i }
    token = JWT.encode(payload, secret, 'HS256')
    jwt_scheme = Arcp::Auth::Jwt.new(secret: secret, algorithms: ['HS256'], audience: 'arcp-runtime')
    with_pair(schemes: [jwt_scheme]) do |client|
      result = client.open(
        auth: { scheme: 'signed_jwt', token: token },
        client: client_identity
      )
      expect(result[:session_id]).to be_a(Arcp::SessionId)
    end
  end

  it 'returns pong on ping after handshake' do
    with_pair(schemes: [bearer]) do |client|
      client.open(
        auth: { scheme: 'bearer', token: 'tok-alice' },
        client: client_identity
      )
      received_at = client.ping
      expect(received_at).to be_a(String)
    end
  end

  it 'nacks unimplemented message types with UNIMPLEMENTED' do
    Sync do
      client_side, runtime_side = Arcp::Transport::Memory.pair
      runtime = Arcp::Runtime::Runtime.new(schemes: [bearer])
      server_task = Async { runtime.serve(runtime_side) }
      client = Arcp::Client::Client.new(transport: client_side)
      begin
        client.open(auth: { scheme: 'bearer', token: 'tok-alice' }, client: client_identity)
        # Send a workflow.start (deferred in v0.1).
        envelope = Arcp::Envelope.build(
          type: 'arcpx.example.workflow.v1',
          payload: { 'foo' => 'bar' },
          session_id: client.session_id
        )
        client_side.send_envelope(envelope)
        response = client_side.receive_envelope
        expect(response.payload).to be_a(Arcp::Messages::Control::Nack)
        expect(response.payload.code).to eq(Arcp::ErrorCode::UNIMPLEMENTED)
      ensure
        client.close
        server_task.wait
      end
    end
  end
end
