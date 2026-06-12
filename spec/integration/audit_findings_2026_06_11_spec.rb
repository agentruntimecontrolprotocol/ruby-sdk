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

  describe 'idempotent resubmission returns the original job.accepted payload (#70)' do
    it 'replays the same credentials, lease, accepted_at and job_id' do
      Sync do
        runtime = build_runtime(
          agents: { worker: ->(ctx) { ctx.finish(result: 'ok') } },
          credential_provisioner: Arcp::Credentials::InMemoryProvisioner.new
        )
        client, server_task = open_pair(runtime)

        first = client.submit_job(agent: 'worker', idempotency_key: 'key-1')
        second = client.submit_job(agent: 'worker', idempotency_key: 'key-1')

        expect(second.job_id).to eq(first.job_id)
        expect(second.credentials).to eq(first.credentials)
        expect(second.credentials).not_to be_nil
        expect(second.lease).to eq(first.lease)
        expect(second.submitted_at).to eq(first.submitted_at)

        client.close
        server_task.stop
      end
    end
  end

  describe 'cancel on a terminal job is a no-op (#71)' do
    it 'does not overwrite terminal status or emit a second terminal event' do
      Sync do
        runtime = build_runtime(agents: { quick: ->(ctx) { ctx.finish(result: 'ok') } })
        client, server_task = open_pair(runtime)

        handle = client.submit_job(agent: 'quick')
        expect(handle.get_result(client: client).result).to eq('ok')

        handle.cancel(client: client, reason: 'too late')
        Async::Task.current.sleep(0.05)

        expect(runtime.job_manager.lookup(handle.job_id).status).to eq('succeeded')

        replay = runtime.event_log.replay_job(handle.job_id, from_event_seq: 0)
        types = replay.map(&:type)
        expect(types).to include(Arcp::MessageTypes::JOB_RESULT)
        expect(types).not_to include(Arcp::MessageTypes::JOB_ERROR)

        client.close
        server_task.stop
      end
    end
  end

  describe 'max_runtime_sec watchdog is cancelled on completion (#72)' do
    it 'completes successfully with no spurious timeout after the deadline' do
      Sync do
        runtime = build_runtime(agents: { fast: ->(ctx) { ctx.finish(result: 'done') } })
        client, server_task = open_pair(runtime)

        handle = client.submit_job(agent: 'fast', max_runtime_sec: 0.05)
        expect(handle.get_result(client: client).result).to eq('done')

        # Sleep past the deadline; a leaked watchdog would wake and fail here.
        Async::Task.current.sleep(0.1)

        expect(runtime.job_manager.lookup(handle.job_id).status).to eq('succeeded')
        types = runtime.event_log.replay_job(handle.job_id, from_event_seq: 0).map(&:type)
        expect(types).not_to include(Arcp::MessageTypes::JOB_ERROR)

        client.close
        server_task.stop
      end
    end
  end

  describe 'job.subscribe history replay is strictly greater than from_event_seq (#75)' do
    it 'excludes the event whose seq equals from_event_seq' do
      Sync do
        runtime = build_runtime(
          agents: { producer: lambda { |ctx|
            5.times { |i| ctx.log(level: 'info', message: "e#{i}") }
            Async::Task.current.sleep(5)
          } },
          tokens: { 'alice-tok' => 'alice', 'obs-tok' => 'alice' }
        )
        submitter, sub_task = open_pair(runtime, auth: { 'token' => 'alice-tok' })
        observer, obs_task = open_pair(runtime, auth: { 'token' => 'obs-tok' })

        handle = submitter.submit_job(agent: 'producer')
        Async::Task.current.sleep(0.05) # let the producer emit all five events

        stream = observer.subscribe_job(job_id: handle.job_id, from_event_seq: 2, history: true)
        replayed = stream.first(3)
        messages = replayed.map { |e| e.body.message }

        # seq 1..5 carry messages e0..e4; from_event_seq:2 must replay seq 3,4,5.
        expect(messages).to eq(%w[e2 e3 e4])

        submitter.close
        observer.close
        sub_task.stop
        obs_task.stop
      end
    end
  end

  describe 'lease_constraints-only submit produces an enforceable lease (#76)' do
    it 'echoes expires_at in job.accepted and enforces expiry' do
      Sync do
        past = (Time.now.utc - 3600).strftime('%Y-%m-%dT%H:%M:%SZ')
        runtime = build_runtime(agents: { sleepy: ->(_ctx) { Async::Task.current.sleep(5) } })
        client, server_task = open_pair(runtime)

        handle = client.submit_job(
          agent: 'sleepy',
          lease_constraints: Arcp::Lease::LeaseConstraints.new(expires_at: past)
        )

        expect(handle.lease).not_to be_nil
        expect(handle.lease.expires_at).to eq(past)
        expect(handle.lease.capabilities).to eq([])

        expect(runtime.lease_manager.get(handle.job_id)).not_to be_nil
        expect do
          runtime.lease_manager.check!(handle.job_id, capability: 'cost.spend')
        end.to raise_error(Arcp::Errors::LeaseExpired)

        client.close
        server_task.stop
      end
    end
  end

  describe 'closing a session detaches its subscriptions (#73)' do
    it 'stops fanout into the closed session outbox for a still-running job' do
      Sync do
        runtime = build_runtime(agents: { sleepy: ->(_ctx) { Async::Task.current.sleep(5) } })
        client, server_task = open_pair(runtime)

        handle = client.submit_job(agent: 'sleepy')
        session_id = client.session.id

        client.close
        Async::Task.current.sleep(0.05)

        # The closed session's rows must be gone from the job's subscriber set.
        subs = runtime.subscription_manager.instance_variable_get(:@subs)[handle.job_id] || []
        expect(subs.map { |(sid, _, _)| sid }).not_to include(session_id)

        server_task.stop
      end
    end
  end
end
