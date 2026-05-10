# frozen_string_literal: true

require 'spec_helper'
require 'async'

RSpec.describe 'cancellation', :integration do
  let(:bearer) { Arcp::Auth::Bearer.new(tokens: { 'tok-alice' => 'alice@example.com' }) }
  let(:client_identity) { { 'kind' => 'rspec', 'version' => '1.0', 'fingerprint' => 'sha256:test' } }

  it 'cancels a running job before it terminates naturally' do
    long_running = lambda do |rt|
      rt.register_tool('long') do |ctx, _args|
        # Cooperatively yields; cancellation propagates as Async::Stop.
        20.times do |i|
          ctx.progress(percent: i * 5)
          ctx.task.sleep(0.05)
        end
        :done
      end
    end

    Sync do
      client_side, runtime_side = Arcp::Transport::Memory.pair
      runtime = Arcp::Runtime::Runtime.new(schemes: [bearer])
      long_running.call(runtime)
      Async { runtime.serve(runtime_side) }
      client = Arcp::Client::Client.new(transport: client_side)
      client.open(auth: { scheme: 'bearer', token: 'tok-alice' }, client: client_identity)

      job_id_holder = []
      events = []
      terminal = nil
      Async do |_task|
        invoke_envelope = Arcp::Envelope.build(
          type: 'tool.invoke',
          payload: Arcp::Messages::Execution::ToolInvoke.new(tool: 'long', arguments: {}),
          session_id: client.session_id
        )
        client_side.send_envelope(invoke_envelope)

        cancelled = false
        loop do
          envelope = client_side.receive_envelope
          break if envelope.nil?

          events << envelope
          job_id_holder << envelope.job_id if envelope.payload.is_a?(Arcp::Messages::Execution::JobAccepted)
          if !cancelled && envelope.payload.is_a?(Arcp::Messages::Execution::JobProgress) && envelope.payload.percent.to_i >= 5
            client.cancel(job_id_holder.first, deadline_ms: 2_000)
            cancelled = true
          end
          next unless envelope.payload.is_a?(Arcp::Messages::Execution::JobCancelled) ||
                      envelope.payload.is_a?(Arcp::Messages::Execution::JobFailed)

          terminal = envelope
          break
        end
      end.wait

      expect(terminal).not_to be_nil
      expect(terminal.payload).to be_a(Arcp::Messages::Execution::JobCancelled)
      client.close
    end
  end

  it 'refuses cancel on a terminal job' do
    Sync do
      client_side, runtime_side = Arcp::Transport::Memory.pair
      runtime = Arcp::Runtime::Runtime.new(schemes: [bearer])
      runtime.register_tool('fast') { |_ctx, _| :ok }
      Async { runtime.serve(runtime_side) }
      client = Arcp::Client::Client.new(transport: client_side)
      client.open(auth: { scheme: 'bearer', token: 'tok-alice' }, client: client_identity)

      result = client.invoke(tool: 'fast')
      expect(result).to be_successful
      job_id = result.job_id

      cancel_envelope = Arcp::Envelope.build(
        type: 'cancel',
        payload: Arcp::Messages::Control::Cancel.new(
          target: 'job', target_id: job_id.value, reason: 'late', deadline_ms: 1_000
        ),
        session_id: client.session_id, job_id: job_id
      )
      client_side.send_envelope(cancel_envelope)
      response = client_side.receive_envelope
      expect(response.payload).to be_a(Arcp::Messages::Control::CancelRefused)
      client.close
    end
  end
end
