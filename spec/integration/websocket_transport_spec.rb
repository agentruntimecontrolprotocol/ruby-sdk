# frozen_string_literal: true

require 'spec_helper'
require 'async'
require 'async/http/endpoint'

RSpec.describe Arcp::Transport::Websocket, :integration do
  let(:bearer) { Arcp::Auth::Bearer.new(tokens: { 'tok-alice' => 'alice@example.com' }) }
  let(:client_identity) { { 'kind' => 'rspec', 'version' => '1.0', 'fingerprint' => 'sha256:test' } }

  def free_port
    server = TCPServer.new('127.0.0.1', 0)
    port = server.addr[1]
    server.close
    port
  end

  it 'round-trips an envelope over a WebSocket' do
    port = free_port
    url = "ws://127.0.0.1:#{port}/"
    Sync do |task|
      runtime = Arcp::Runtime::Runtime.new(schemes: [bearer])
      runtime.register_tool('echo') { |_ctx, args| args }

      endpoint = Async::HTTP::Endpoint.parse(url)
      server = described_class::Server.new(endpoint: endpoint)
      server_task = task.async do
        server.run { |transport| runtime.serve(transport) }
      rescue StandardError
        # task stop
      end

      # Wait for the server to actually start listening.
      ready = false
      until ready
        begin
          TCPSocket.new('127.0.0.1', port).close
          ready = true
        rescue Errno::ECONNREFUSED
          task.sleep(0.05)
        end
      end

      transport = described_class.connect(url)
      client = Arcp::Client::Client.new(transport: transport)
      begin
        client.open(auth: { scheme: 'bearer', token: 'tok-alice' }, client: client_identity)
        result = client.invoke(tool: 'echo', arguments: { 'hello' => 'ws' })
        expect(result).to be_successful
        expect(result.value).to eq('hello' => 'ws')
      ensure
        client.close
        server_task.stop
      end
    end
  end
end
