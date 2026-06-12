# frozen_string_literal: true

require 'spec_helper'
require 'bigdecimal'

RSpec.describe 'audit findings 2026-06-11 (integration)', type: :integration do
  describe 'malformed inbound messages keep the session alive (#69)' do
    it 'replies INVALID_REQUEST and continues serving the session' do
      Sync do
        runtime = build_runtime(agents: { sleepy: ->(_ctx) { Async::Task.current.sleep(5) } })
        a = Async::Queue.new
        b = Async::Queue.new
        server_t = DecodingMemoryTransport.new(incoming: a, outgoing: b)
        client_t = Arcp::Transport::MemoryTransport.new(incoming: b, outgoing: a)
        server_task = Async { runtime.accept(server_t) }

        sid = Arcp::Ids.session_id
        hello = Arcp::Session::Hello.new(
          client_name: 'spec', client_version: '1',
          auth: { 'token' => 'demo' },
          capabilities: Arcp::Session::CapabilitySet.local, resume: nil
        )
        client_t.send(Arcp::Envelope.build(
                        type: Arcp::MessageTypes::SESSION_HELLO, session_id: sid, payload: hello.to_h
                      ))
        expect(client_t.receive.type).to eq(Arcp::MessageTypes::SESSION_WELCOME)

        # (1) Malformed envelope: unsupported arcp version -> decode raises.
        a.enqueue(
          'arcp' => '0.0.0', 'id' => Arcp::Ids.envelope_id,
          'type' => Arcp::MessageTypes::JOB_SUBMIT, 'session_id' => sid, 'payload' => {}
        )
        err1 = client_t.receive
        expect(err1.type).to eq(Arcp::MessageTypes::SESSION_ERROR)
        expect(err1.payload['code']).to eq('INVALID_REQUEST')

        # (2) Valid envelope but job.submit missing required 'agent'.
        client_t.send(Arcp::Envelope.build(
                        type: Arcp::MessageTypes::JOB_SUBMIT, session_id: sid, payload: {}
                      ))
        err2 = client_t.receive
        expect(err2.type).to eq(Arcp::MessageTypes::SESSION_ERROR)
        expect(err2.payload['code']).to eq('INVALID_REQUEST')

        # (3) The session still accepts subsequent valid messages.
        submit = Arcp::Job::Submit.new(
          agent: 'sleepy', input: nil, lease_request: nil,
          lease_constraints: nil, idempotency_key: nil, max_runtime_sec: nil
        )
        client_t.send(Arcp::Envelope.build(
                        type: Arcp::MessageTypes::JOB_SUBMIT, session_id: sid, payload: submit.to_h
                      ))
        expect(client_t.receive.type).to eq(Arcp::MessageTypes::JOB_ACCEPTED)

        client_t.close
        server_task.stop
      end
    end
  end
end
