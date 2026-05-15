# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'agent versioning', type: :integration do
  it 'resolves bare names to default and rejects unknown versions' do
    Sync do
      runtime = Arcp::Runtime::Runtime.new(
        auth_verifier: Arcp::Auth::Bearer.from_token('demo', principal_id: 'alice'),
        heartbeat_interval_sec: nil
      )
      runtime.register_agent(
        name: 'code-refactor', versions: %w[1.0.0 2.0.0], default: '2.0.0',
        handler: ->(ctx) { ctx.finish(result: 'ok') }
      )

      server_t, client_t = Arcp::Transport::MemoryTransport.pair
      task = Async { runtime.accept(server_t) }
      client = Arcp::Client.open(transport: client_t, auth: { 'token' => 'demo' })

      expect(client.submit_job(agent: 'code-refactor').agent).to eq('code-refactor@2.0.0')
      expect(client.submit_job(agent: 'code-refactor@1.0.0').agent).to eq('code-refactor@1.0.0')

      expect do
        client.submit_job(agent: 'code-refactor@9.9.9')
      end.to raise_error(Arcp::Errors::AgentVersionNotAvailable)

      client.close
      task.stop
    end
  end
end
