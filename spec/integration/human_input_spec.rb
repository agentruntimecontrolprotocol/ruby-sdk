# frozen_string_literal: true

require 'spec_helper'
require 'async'

RSpec.describe 'human-in-the-loop', :integration do
  let(:bearer) { Arcp::Auth::Bearer.new(tokens: { 'tok-alice' => 'alice@example.com' }) }
  let(:client_identity) { { 'kind' => 'rspec', 'version' => '1.0', 'fingerprint' => 'sha256:test' } }

  it 'requests human input and resolves on the first response' do
    Sync do
      client_side, runtime_side = Arcp::Transport::Memory.pair
      runtime = Arcp::Runtime::Runtime.new(schemes: [bearer])
      runtime.register_tool('ask') do |ctx, _args|
        ctx.request_human_input(
          prompt: 'pick a branch',
          response_schema: { 'type' => 'object',
                             'properties' => { 'branch' => { 'type' => 'string' } },
                             'required' => ['branch'] }
        )
      end
      Async { runtime.serve(runtime_side) }
      client = Arcp::Client::Client.new(transport: client_side)
      client.open(auth: { scheme: 'bearer', token: 'tok-alice' }, client: client_identity)
      client.on_human_input { |_env| { 'branch' => 'feat/foo' } }

      result = client.invoke(tool: 'ask')
      expect(result).to be_successful
      expect(result.value).to eq('branch' => 'feat/foo')
      client.close
    end
  end

  it 'falls back to default on expiration when one is set' do
    Sync do
      client_side, runtime_side = Arcp::Transport::Memory.pair
      runtime = Arcp::Runtime::Runtime.new(schemes: [bearer])
      runtime.register_tool('ask-with-default') do |ctx, _args|
        ctx.request_human_input(
          prompt: 'pick',
          default: { 'branch' => 'auto' },
          expires_in_seconds: 0.05
        )
      end
      Async { runtime.serve(runtime_side) }
      client = Arcp::Client::Client.new(transport: client_side)
      client.open(auth: { scheme: 'bearer', token: 'tok-alice' }, client: client_identity)
      # No on_human_input handler — let it expire.

      result = client.invoke(tool: 'ask-with-default')
      expect(result).to be_successful
      expect(result.value).to eq('branch' => 'auto')
      client.close
    end
  end

  it 'fails the job on expiration when no default is set' do
    Sync do
      client_side, runtime_side = Arcp::Transport::Memory.pair
      runtime = Arcp::Runtime::Runtime.new(schemes: [bearer])
      runtime.register_tool('ask-no-default') do |ctx, _args|
        ctx.request_human_input(prompt: 'pick', expires_in_seconds: 0.05)
      end
      Async { runtime.serve(runtime_side) }
      client = Arcp::Client::Client.new(transport: client_side)
      client.open(auth: { scheme: 'bearer', token: 'tok-alice' }, client: client_identity)

      result = client.invoke(tool: 'ask-no-default')
      expect(result).not_to be_successful
      expect(result.terminal.payload).to be_a(Arcp::Messages::Execution::JobFailed)
      expect(result.terminal.payload.code).to eq(Arcp::ErrorCode::DEADLINE_EXCEEDED)
      client.close
    end
  end

  it 'raises INVALID_ARGUMENT on schema-violating responses' do
    Sync do
      client_side, runtime_side = Arcp::Transport::Memory.pair
      runtime = Arcp::Runtime::Runtime.new(schemes: [bearer])
      runtime.register_tool('strict') do |ctx, _args|
        ctx.request_human_input(
          prompt: 'pick',
          response_schema: { 'type' => 'object',
                             'properties' => { 'branch' => { 'type' => 'string' } },
                             'required' => ['branch'] }
        )
      end
      Async { runtime.serve(runtime_side) }
      client = Arcp::Client::Client.new(transport: client_side)
      client.open(auth: { scheme: 'bearer', token: 'tok-alice' }, client: client_identity)
      client.on_human_input { |_env| { 'wrong' => 'shape' } }

      result = client.invoke(tool: 'strict')
      expect(result).not_to be_successful
      expect(result.terminal.payload).to be_a(Arcp::Messages::Execution::JobFailed)
      expect(result.terminal.payload.code).to eq(Arcp::ErrorCode::INVALID_ARGUMENT)
      client.close
    end
  end
end
