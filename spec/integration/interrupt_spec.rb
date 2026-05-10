# frozen_string_literal: true

require 'spec_helper'
require 'async'

RSpec.describe 'interrupt', :integration do
  let(:bearer) { Arcp::Auth::Bearer.new(tokens: { 'tok-alice' => 'alice@example.com' }) }
  let(:client_identity) { { 'kind' => 'rspec', 'version' => '1.0', 'fingerprint' => 'sha256:test' } }

  it 'pauses a running job and emits human.input.request' do
    Sync do
      client_side, runtime_side = Arcp::Transport::Memory.pair
      runtime = Arcp::Runtime::Runtime.new(schemes: [bearer])
      runtime.register_tool('long') do |ctx, _args|
        20.times do |i|
          ctx.progress(percent: i * 5)
          ctx.task.sleep(0.05)
        end
      end
      Async { runtime.serve(runtime_side) }
      client = Arcp::Client::Client.new(transport: client_side)
      client.open(auth: { scheme: 'bearer', token: 'tok-alice' }, client: client_identity)

      invoke = Arcp::Envelope.build(
        type: 'tool.invoke',
        payload: Arcp::Messages::Execution::ToolInvoke.new(tool: 'long', arguments: {}),
        session_id: client.session_id
      )
      client_side.send_envelope(invoke)

      job_id = nil
      input_request = nil
      sent_interrupt = false
      loop do
        envelope = client_side.receive_envelope
        break if envelope.nil?

        case envelope.payload
        when Arcp::Messages::Execution::JobAccepted
          job_id = envelope.job_id
        when Arcp::Messages::Execution::JobProgress
          if !sent_interrupt && envelope.payload.percent.to_i >= 5
            interrupt = Arcp::Envelope.build(
              type: 'interrupt',
              payload: Arcp::Messages::Control::Interrupt.new(
                target: 'job', target_id: job_id.value, prompt: 'pause please'
              ),
              session_id: client.session_id, job_id: job_id
            )
            client_side.send_envelope(interrupt)
            sent_interrupt = true
          end
        when Arcp::Messages::Human::InputRequest
          input_request = envelope
          # Cancel to clean up
          client.cancel(job_id, deadline_ms: 1_000)
        when Arcp::Messages::Execution::JobCancelled, Arcp::Messages::Execution::JobCompleted
          break
        end
      end

      expect(input_request).not_to be_nil
      expect(input_request.payload.prompt).to eq('pause please')
      expect(input_request.job_id).to eq(job_id)
      client.close
    end
  end
end
