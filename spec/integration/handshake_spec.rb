# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'session handshake', type: :integration do
  it 'completes hello → welcome with intersected capabilities' do
    Sync do
      runtime = build_runtime
      client, server_task = open_pair(runtime)

      expect(client.session.runtime_version).to eq(Arcp::VERSION)
      expect(client.session.capabilities.supports?(Arcp::Session::Feature::HEARTBEAT)).to be(true)
      expect(client.session.resume_token).not_to be_nil

      client.close
      server_task.stop
    end
  end

  it 'rejects invalid bearer tokens with UNAUTHENTICATED' do
    Sync do
      runtime = build_runtime
      server_t, client_t = Arcp::Transport::MemoryTransport.pair
      server_task = Async { runtime.accept(server_t) }

      expect do
        Arcp::Client.open(transport: client_t, auth: { 'token' => 'nope' }, client_name: 'spec')
      end.to raise_error(Arcp::Errors::Unauthenticated)

      server_task.stop
    end
  end
end
