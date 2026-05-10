# frozen_string_literal: true

require 'spec_helper'
require 'async'

RSpec.describe 'unknown message handling', :integration do
  let(:bearer) { Arcp::Auth::Bearer.new(tokens: { 'tok-alice' => 'alice@example.com' }) }
  let(:client_identity) { { 'kind' => 'rspec', 'version' => '1.0', 'fingerprint' => 'sha256:test' } }

  it 'returns UNIMPLEMENTED for unknown namespaced types' do
    Sync do
      client_side, runtime_side = Arcp::Transport::Memory.pair
      runtime = Arcp::Runtime::Runtime.new(schemes: [bearer])
      Async { runtime.serve(runtime_side) }
      client = Arcp::Client::Client.new(transport: client_side)
      client.open(auth: { scheme: 'bearer', token: 'tok-alice' }, client: client_identity)

      envelope = Arcp::Envelope.build(
        type: 'arcpx.example.foo.v1',
        payload: { foo: 'bar' },
        session_id: client.session_id
      )
      client_side.send_envelope(envelope)
      response = client_side.receive_envelope
      expect(response.payload).to be_a(Arcp::Messages::Control::Nack)
      expect(response.payload.code).to eq(Arcp::ErrorCode::UNIMPLEMENTED)
      client.close
    end
  end
end
