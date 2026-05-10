# frozen_string_literal: true

require 'spec_helper'
require 'async'

RSpec.describe 'job lifecycle', :integration do
  let(:bearer) { Arcp::Auth::Bearer.new(tokens: { 'tok-alice' => 'alice@example.com' }) }
  let(:client_identity) { { 'kind' => 'rspec', 'version' => '1.0', 'fingerprint' => 'sha256:test' } }

  def with_runtime(tools_block: nil)
    Sync do
      client_side, runtime_side = Arcp::Transport::Memory.pair
      runtime = Arcp::Runtime::Runtime.new(schemes: [bearer])
      tools_block&.call(runtime)
      server_task = Async { runtime.serve(runtime_side) }
      client = Arcp::Client::Client.new(transport: client_side)
      client.open(auth: { scheme: 'bearer', token: 'tok-alice' }, client: client_identity)
      begin
        yield client
      ensure
        client.close
        server_task.wait
      end
    end
  end

  it 'runs a synchronous tool to completion' do
    register = ->(rt) { rt.register_tool('echo') { |_ctx, args| { ok: true, args: args } } }
    with_runtime(tools_block: register) do |client|
      result = client.invoke(tool: 'echo', arguments: { hello: 'world' })
      expect(result).to be_successful
      expect(result.value).to eq(ok: true, args: { hello: 'world' })
    end
  end

  it 'streams progress and heartbeat events' do
    register = lambda do |rt|
      rt.register_tool('progress') do |ctx, _args|
        ctx.heartbeat
        ctx.progress(percent: 25, message: 'quarter')
        ctx.progress(percent: 75, message: 'most')
        :done
      end
    end
    with_runtime(tools_block: register) do |client|
      result = client.invoke(tool: 'progress')
      kinds = result.events.map { |e| e.payload.class }
      expect(kinds).to include(
        Arcp::Messages::Execution::JobAccepted,
        Arcp::Messages::Execution::JobStarted,
        Arcp::Messages::Execution::JobHeartbeat,
        Arcp::Messages::Execution::JobProgress,
        Arcp::Messages::Execution::JobCompleted
      )
      progress_events = result.events.select { |e| e.payload.is_a?(Arcp::Messages::Execution::JobProgress) }
      expect(progress_events.map { |e| e.payload.percent }).to eq([25, 75])
    end
  end

  it 'fails the job when the tool raises' do
    register = lambda do |rt|
      rt.register_tool('boom') do |_ctx, _args|
        raise Arcp::Error::Internal, 'kaboom'
      end
    end
    with_runtime(tools_block: register) do |client|
      result = client.invoke(tool: 'boom')
      expect(result).not_to be_successful
      payload = result.terminal.payload
      expect(payload).to be_a(Arcp::Messages::Execution::JobFailed)
      expect(payload.code).to eq(Arcp::ErrorCode::INTERNAL)
      expect(payload.message).to eq('kaboom')
    end
  end

  it 'rejects unknown tools with NOT_FOUND' do
    with_runtime do |client|
      result = client.invoke(tool: 'missing')
      expect(result.terminal.payload).to be_a(Arcp::Messages::Execution::ToolError)
      expect(result.terminal.payload.code).to eq(Arcp::ErrorCode::NOT_FOUND)
    end
  end
end
