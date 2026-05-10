# frozen_string_literal: true

require 'spec_helper'
require 'async'

RSpec.describe 'resume', :integration do
  let(:bearer) { Arcp::Auth::Bearer.new(tokens: { 'tok-alice' => 'alice@example.com' }) }
  let(:client_identity) { { 'kind' => 'rspec', 'version' => '1.0', 'fingerprint' => 'sha256:test' } }

  it 'replays events strictly after a given message id' do
    Sync do
      client_side, runtime_side = Arcp::Transport::Memory.pair
      runtime = Arcp::Runtime::Runtime.new(schemes: [bearer])
      runtime.register_tool('emit-three') do |ctx, _args|
        ctx.progress(percent: 10)
        ctx.progress(percent: 20)
        ctx.progress(percent: 30)
        :done
      end
      Async { runtime.serve(runtime_side) }
      client = Arcp::Client::Client.new(transport: client_side)
      client.open(auth: { scheme: 'bearer', token: 'tok-alice' }, client: client_identity)
      result = client.invoke(tool: 'emit-three')
      expect(result).to be_successful

      first_progress = result.events.find { |e| e.payload.is_a?(Arcp::Messages::Execution::JobProgress) }
      resume_envelope = Arcp::Envelope.build(
        type: 'resume',
        payload: Arcp::Messages::Control::Resume.new(
          after_message_id: first_progress.id.value, checkpoint_id: nil, include_open_streams: false
        ),
        session_id: client.session_id
      )
      client_side.send_envelope(resume_envelope)

      replayed = []
      ack = nil
      until ack
        envelope = client_side.receive_envelope
        break if envelope.nil?

        if envelope.payload.is_a?(Arcp::Messages::Control::Ack)
          ack = envelope
        else
          replayed << envelope
        end
      end
      expect(ack).not_to be_nil
      progress_after = replayed.select { |e| e.payload.is_a?(Arcp::Messages::Execution::JobProgress) }
      expect(progress_after.map { |e| e.payload.percent }).to eq([20, 30])
      client.close
    end
  end

  it 'returns UNIMPLEMENTED for checkpoint-based resume' do
    Sync do
      client_side, runtime_side = Arcp::Transport::Memory.pair
      runtime = Arcp::Runtime::Runtime.new(schemes: [bearer])
      Async { runtime.serve(runtime_side) }
      client = Arcp::Client::Client.new(transport: client_side)
      client.open(auth: { scheme: 'bearer', token: 'tok-alice' }, client: client_identity)
      env = Arcp::Envelope.build(
        type: 'resume',
        payload: Arcp::Messages::Control::Resume.new(
          after_message_id: nil, checkpoint_id: 'chk_x', include_open_streams: false
        ),
        session_id: client.session_id
      )
      client_side.send_envelope(env)
      response = client_side.receive_envelope
      expect(response.payload).to be_a(Arcp::Messages::Control::Nack)
      expect(response.payload.code).to eq(Arcp::ErrorCode::UNIMPLEMENTED)
      client.close
    end
  end
end
