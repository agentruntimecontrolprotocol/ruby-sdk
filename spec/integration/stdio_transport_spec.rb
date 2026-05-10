# frozen_string_literal: true

require 'spec_helper'
require 'async'

RSpec.describe Arcp::Transport::Stdio, :integration do
  let(:bearer) { Arcp::Auth::Bearer.new(tokens: { 'tok-alice' => 'alice@example.com' }) }
  let(:client_identity) { { 'kind' => 'rspec', 'version' => '1.0', 'fingerprint' => 'sha256:test' } }

  it 'round-trips an envelope through a pair of pipes' do
    Sync do
      client_to_runtime_r, client_to_runtime_w = IO.pipe
      runtime_to_client_r, runtime_to_client_w = IO.pipe

      runtime_transport = described_class.new(input: client_to_runtime_r, output: runtime_to_client_w)
      client_transport = described_class.new(input: runtime_to_client_r, output: client_to_runtime_w)

      runtime = Arcp::Runtime::Runtime.new(schemes: [bearer])
      runtime.register_tool('echo') { |_ctx, args| args }
      Async { runtime.serve(runtime_transport) }

      client = Arcp::Client::Client.new(transport: client_transport)
      client.open(auth: { scheme: 'bearer', token: 'tok-alice' }, client: client_identity)
      result = client.invoke(tool: 'echo', arguments: { 'hello' => 'stdio' })
      expect(result).to be_successful
      expect(result.value).to eq('hello' => 'stdio')
      client.close
    end
  end
end
