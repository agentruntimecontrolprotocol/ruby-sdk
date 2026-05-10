# frozen_string_literal: true

require 'spec_helper'
require 'async'

RSpec.describe 'subscriptions', :integration do
  let(:bearer) { Arcp::Auth::Bearer.new(tokens: { 'tok-alice' => 'alice@example.com' }) }
  let(:client_identity) { { 'kind' => 'rspec', 'version' => '1.0', 'fingerprint' => 'sha256:test' } }

  it 'subscribes and observes a backfill_complete marker' do
    Sync do
      client_side, runtime_side = Arcp::Transport::Memory.pair
      runtime = Arcp::Runtime::Runtime.new(schemes: [bearer])
      runtime.register_tool('emit') do |ctx, _args|
        ctx.progress(percent: 50, message: 'half')
        :done
      end
      Async { runtime.serve(runtime_side) }
      client = Arcp::Client::Client.new(transport: client_side)
      client.open(auth: { scheme: 'bearer', token: 'tok-alice' }, client: client_identity)
      result = client.invoke(tool: 'emit')
      expect(result).to be_successful

      sub_envelope = Arcp::Envelope.build(
        type: 'subscribe',
        payload: Arcp::Messages::Subscriptions::Subscribe.new(
          filter: { 'session_id' => [client.session_id.value],
                    'types' => ['job.progress'] },
          since: nil
        ),
        session_id: client.session_id
      )
      client_side.send_envelope(sub_envelope)
      accepted = client_side.receive_envelope
      expect(accepted.payload).to be_a(Arcp::Messages::Subscriptions::SubscribeAccepted)

      backfill_events = []
      until backfill_events.any? { |e| e.dig(:payload, :name) == 'subscription.backfill_complete' }
        envelope = client_side.receive_envelope
        break if envelope.nil?

        wrapped = envelope.payload
        next unless wrapped.is_a?(Arcp::Messages::Subscriptions::SubscribeEvent)

        backfill_events << wrapped.event
      end

      progress = backfill_events.find { |e| e[:type] == 'job.progress' }
      expect(progress).not_to be_nil
      expect(progress.dig(:payload, :percent)).to eq(50)
      client.close
    end
  end

  it 'rejects subscribing to another session with PERMISSION_DENIED' do
    Sync do
      client_side, runtime_side = Arcp::Transport::Memory.pair
      runtime = Arcp::Runtime::Runtime.new(schemes: [bearer])
      Async { runtime.serve(runtime_side) }
      client = Arcp::Client::Client.new(transport: client_side)
      client.open(auth: { scheme: 'bearer', token: 'tok-alice' }, client: client_identity)

      sub_envelope = Arcp::Envelope.build(
        type: 'subscribe',
        payload: Arcp::Messages::Subscriptions::Subscribe.new(
          filter: { 'session_id' => ['sess_other'] }, since: nil
        ),
        session_id: client.session_id
      )
      client_side.send_envelope(sub_envelope)
      response = client_side.receive_envelope
      expect(response.payload).to be_a(Arcp::Messages::Control::Nack)
      expect(response.payload.code).to eq(Arcp::ErrorCode::PERMISSION_DENIED)
      client.close
    end
  end
end
