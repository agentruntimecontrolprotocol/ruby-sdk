# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Arcp::Envelope do
  it 'builds with the v1 wire fields' do
    env = described_class.build(
      type: 'session.hello', session_id: 's_1',
      payload: { 'features' => ['heartbeat'] }
    )
    expect(env.arcp).to eq('1')
    expect(env.type).to eq('session.hello')
    expect(env.session_id).to eq('s_1')
    expect(env.event_seq).to be_nil
  end

  it 'round-trips through JSON' do
    env = described_class.build(
      type: 'job.event', session_id: 's_1', job_id: 'j_1', event_seq: 7,
      payload: { 'kind' => 'log', 'body' => { 'level' => 'info', 'message' => 'hi' } }
    )
    again = described_class.from_json(env.to_json)
    expect(again).to eq(env)
  end

  it 'rejects unsupported arcp version' do
    expect do
      described_class.from_h(
        'arcp' => '2', 'id' => 'x', 'type' => 'session.hello', 'session_id' => 's', 'payload' => {}
      )
    end.to raise_error(Arcp::Errors::InvalidRequest)
  end

  it 'rejects non-Integer event_seq' do
    expect do
      described_class.from_h(
        'arcp' => '1', 'id' => 'x', 'type' => 'job.event', 'session_id' => 's',
        'event_seq' => '7', 'payload' => {}
      )
    end.to raise_error(Arcp::Errors::InvalidRequest)
  end

  it 'rejects malformed trace_id' do
    expect do
      described_class.build(
        type: 'session.hello', session_id: 's', trace_id: 'not-hex', payload: {}
      )
    end.to raise_error(Arcp::Errors::InvalidRequest)
  end
end
