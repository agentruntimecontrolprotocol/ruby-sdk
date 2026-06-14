# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'audit findings 2026-05-28 (integration)', type: :integration do
  describe "completed jobs list with status 'success' (#49)" do
    it 'reports the spec terminal value, not succeeded' do
      Sync do
        runtime = build_runtime(agents: { echo: ->(ctx) { ctx.finish(result: 'ok') } })
        client, server_task = open_pair(runtime)

        handle = client.submit_job(agent: 'echo')
        handle.get_result(client: client)
        Async::Task.current.sleep(0.02)

        expect(runtime.job_manager.lookup(handle.job_id).status).to eq('success')
        listed = client.list_jobs(status: ['success']).to_a
        expect(listed.map(&:status)).to all(eq('success'))
        expect(listed.size).to eq(1)

        client.close
        server_task.stop
      end
    end
  end

  describe "timed-out jobs terminate with final_status 'timed_out' (#48)" do
    it 'does not report a generic error final_status' do
      Sync do
        runtime = build_runtime(agents: { slow: ->(_ctx) { Async::Task.current.sleep(5) } })
        client, server_task = open_pair(runtime)

        handle = client.submit_job(agent: 'slow', max_runtime_sec: 0.05)
        expect { handle.get_result(client: client) }.to raise_error(Arcp::Error)
        Async::Task.current.sleep(0.05)

        expect(runtime.job_manager.lookup(handle.job_id).status).to eq('timed_out')
        err = runtime.event_log
                     .replay_job(handle.job_id, from_event_seq: 0)
                     .find { |e| e.type == Arcp::MessageTypes::JOB_ERROR }
        expect(err.payload['final_status']).to eq('timed_out')
        expect(err.payload['code']).to eq('TIMEOUT')

        client.close
        server_task.stop
      end
    end
  end

  describe 'cost.* metrics decrement the budget and enforce exhaustion (#44)' do
    it 'decrements budget on cost metrics and yields BUDGET_EXHAUSTED at the operation boundary' do
      Sync do
        lease_mgr = nil
        remaining_after_first = nil
        remaining_when_exhausted = nil
        runtime = build_runtime(
          agents: { spender: lambda { |ctx|
            ctx.metric(name: 'cost.inference', value: '0.30', unit: 'USD')
            remaining_after_first = lease_mgr.remaining(ctx.job_id)['USD']
            ctx.metric(name: 'cost.inference', value: '0.90', unit: 'USD')
            remaining_when_exhausted = lease_mgr.remaining(ctx.job_id)['USD']
            ctx.authorize!('cost.spend') # operation boundary after exhaustion
            ctx.finish(result: 'unreachable')
          } }
        )
        lease_mgr = runtime.lease_manager
        client, server_task = open_pair(runtime)

        handle = client.submit_job(
          agent: 'spender',
          lease_request: Arcp::Lease::LeaseRequest.new(
            capabilities: ['cost.spend'],
            budget: Arcp::Lease::CostBudget.parse(['USD:1.00'])
          )
        )

        expect { handle.get_result(client: client) }.to raise_error(Arcp::Errors::BudgetExhausted)
        expect(remaining_after_first).to eq(BigDecimal('0.70'))
        expect(remaining_when_exhausted).to eq(BigDecimal('0'))

        client.close
        server_task.stop
      end
    end

    it 'rejects a negative cost metric' do
      Sync do
        runtime = build_runtime(
          agents: { bad: lambda { |ctx|
            ctx.metric(name: 'cost.inference', value: '-1.00', unit: 'USD')
            ctx.finish(result: 'unreachable')
          } }
        )
        client, server_task = open_pair(runtime)
        handle = client.submit_job(
          agent: 'bad',
          lease_request: Arcp::Lease::LeaseRequest.new(
            capabilities: ['cost.spend'], budget: Arcp::Lease::CostBudget.parse(['USD:1.00'])
          )
        )
        expect { handle.get_result(client: client) }.to raise_error(Arcp::Errors::InvalidRequest)
        client.close
        server_task.stop
      end
    end
  end

  describe 'lease and model enforcement primitives are invoked (#45)' do
    it 'raises PERMISSION_DENIED for a capability outside the lease' do
      Sync do
        runtime = build_runtime(
          agents: { agent: ->(ctx) { ctx.authorize!('net.fetch') && ctx.finish(result: 'ok') } }
        )
        client, server_task = open_pair(runtime)
        handle = client.submit_job(
          agent: 'agent',
          lease_request: Arcp::Lease::LeaseRequest.new(capabilities: ['fs.read'])
        )
        expect { handle.get_result(client: client) }.to raise_error(Arcp::Errors::PermissionDenied)
        client.close
        server_task.stop
      end
    end

    it 'admits a capability inside the lease' do
      Sync do
        runtime = build_runtime(
          agents: { agent: ->(ctx) { ctx.authorize!('fs.read') && ctx.finish(result: 'ok') } }
        )
        client, server_task = open_pair(runtime)
        handle = client.submit_job(
          agent: 'agent',
          lease_request: Arcp::Lease::LeaseRequest.new(capabilities: ['fs.read'])
        )
        expect(handle.get_result(client: client).result).to eq('ok')
        client.close
        server_task.stop
      end
    end

    it 'raises PERMISSION_DENIED for a model outside model.use' do
      Sync do
        runtime = build_runtime(
          agents: { llm: ->(ctx) { ctx.use_model!('anthropic/claude-3-opus') && ctx.finish(result: 'ok') } }
        )
        client, server_task = open_pair(runtime)
        handle = client.submit_job(
          agent: 'llm',
          lease_request: Arcp::Lease::LeaseRequest.new(
            capabilities: ['model.call'], model_use: ['tier-fast/*']
          )
        )
        expect { handle.get_result(client: client) }.to raise_error(Arcp::Errors::PermissionDenied)
        client.close
        server_task.stop
      end
    end
  end

  describe 'submission rejects a past expires_at (#46)' do
    it 'raises INVALID_REQUEST for an expires_at at or before now' do
      Sync do
        clock = Arcp::FakeClock.new
        runtime = build_runtime(
          agents: { sleepy: ->(_ctx) { Async::Task.current.sleep(5) } }, clock: clock
        )
        client, server_task = open_pair(runtime, clock: clock)

        past = (clock.now - 3600).iso8601
        expect do
          client.submit_job(
            agent: 'sleepy',
            lease_constraints: Arcp::Lease::LeaseConstraints.new(expires_at: past)
          )
        end.to raise_error(Arcp::Errors::InvalidRequest)

        client.close
        server_task.stop
      end
    end
  end

  describe 'event_seq is session-scoped across a session\'s jobs (#43)' do
    it 'assigns strictly increasing, gap-free seqs across two jobs in one session' do
      Sync do
        runtime = build_runtime(
          agents: { emitter: lambda { |ctx|
            3.times { |i| ctx.log(level: 'info', message: "m#{i}") }
            Async::Task.current.sleep(5)
          } }
        )
        client, server_task = open_pair(runtime)

        client.submit_job(agent: 'emitter')
        client.submit_job(agent: 'emitter')
        Async::Task.current.sleep(0.1)

        session_id = client.session.id
        seqs = runtime.event_log
                      .replay(session_id)
                      .select { |e| e.type == Arcp::MessageTypes::JOB_EVENT }
                      .map(&:event_seq)

        expect(seqs.size).to eq(6)
        expect(seqs.uniq).to eq(seqs)        # no repeats across the two jobs
        expect(seqs).to eq(seqs.sort)        # strictly monotonic
        expect(seqs).to eq((1..6).to_a)      # gap-free from 1

        client.close
        server_task.stop
      end
    end
  end

  describe 'job.subscribed carries the required fields (#51)' do
    it 'includes current_status, agent and lease on attach' do
      Sync do
        runtime = build_runtime(
          agents: { worker: ->(_ctx) { Async::Task.current.sleep(5) } },
          tokens: { 'alice' => 'alice' }
        )
        submitter, sub_task = open_pair(runtime, auth: { 'token' => 'alice' })
        handle = submitter.submit_job(
          agent: 'worker',
          lease_request: Arcp::Lease::LeaseRequest.new(capabilities: ['tool.call'])
        )
        Async::Task.current.sleep(0.02)

        obs_server, obs_client = Arcp::Transport::MemoryTransport.pair
        obs_task = Async { runtime.accept(obs_server) }
        sid = Arcp::Ids.session_id
        hello = Arcp::Session::Hello.new(
          client_name: 'obs', client_version: '1', auth: { 'token' => 'alice' },
          capabilities: Arcp::Session::CapabilitySet.local, resume: nil
        )
        obs_client.send(Arcp::Envelope.build(
                          type: Arcp::MessageTypes::SESSION_HELLO, session_id: sid, payload: hello.to_h
                        ))
        expect(obs_client.receive.type).to eq(Arcp::MessageTypes::SESSION_WELCOME)

        obs_client.send(Arcp::Envelope.build(
                          type: Arcp::MessageTypes::JOB_SUBSCRIBE, session_id: sid, job_id: handle.job_id,
                          payload: Arcp::Job::Subscribe.new(
                            job_id: handle.job_id, from_event_seq: nil, history: false
                          ).to_h
                        ))
        subscribed_env = obs_client.receive
        expect(subscribed_env.type).to eq(Arcp::MessageTypes::JOB_SUBSCRIBED)

        payload = Arcp::Job::Subscribed.from_h(subscribed_env.payload)
        expect(payload.current_status).to eq('running')
        expect(payload.agent).to eq('worker@1.0.0')
        expect(payload.lease).not_to be_nil
        expect(payload.lease.capabilities).to include('tool.call')
        expect(payload.replayed).to be(false)

        submitter.close
        obs_client.close
        sub_task.stop
        obs_task.stop
      end
    end
  end

  describe 'idempotency conflict detection compares all parameters (#50)' do
    it 'raises DUPLICATE_KEY when the same key is reused with a different input' do
      Sync do
        runtime = build_runtime(agents: { worker: ->(ctx) { ctx.finish(result: 'ok') } })
        client, server_task = open_pair(runtime)

        first = client.submit_job(agent: 'worker', input: { 'n' => 1 }, idempotency_key: 'k')
        expect(first.job_id).not_to be_nil

        expect do
          client.submit_job(agent: 'worker', input: { 'n' => 2 }, idempotency_key: 'k')
        end.to raise_error(Arcp::Errors::DuplicateKey)

        # Same key + identical params is still a replay, not a conflict.
        replay = client.submit_job(agent: 'worker', input: { 'n' => 1 }, idempotency_key: 'k')
        expect(replay.job_id).to eq(first.job_id)

        client.close
        server_task.stop
      end
    end
  end

  describe 'cancellation emits job.cancelled then job.error (#47)' do
    it 'acknowledges with job.cancelled before the CANCELLED job.error' do
      Sync do
        runtime = build_runtime(agents: { slow: ->(_ctx) { Async::Task.current.sleep(5) } })
        client, server_task = open_pair(runtime)

        handle = client.submit_job(agent: 'slow')
        Async::Task.current.sleep(0.02)
        handle.cancel(client: client, reason: 'user requested')
        Async::Task.current.sleep(0.05)

        replay = runtime.event_log.replay_job(handle.job_id, from_event_seq: 0)
        types = replay.map(&:type)
        cancelled_idx = types.index(Arcp::MessageTypes::JOB_CANCELLED)
        error_idx = types.index(Arcp::MessageTypes::JOB_ERROR)

        expect(cancelled_idx).not_to be_nil
        expect(error_idx).not_to be_nil
        expect(cancelled_idx).to be < error_idx

        cancelled = replay[cancelled_idx]
        expect(cancelled.payload['job_id']).to eq(handle.job_id)
        expect(cancelled.payload['reason']).to eq('user requested')

        error = replay[error_idx]
        expect(error.payload['code']).to eq('CANCELLED')
        expect(error.payload['final_status']).to eq('cancelled')

        client.close
        server_task.stop
      end
    end
  end

  describe 'list_jobs honors the created_after filter (#57)' do
    it 'excludes jobs created at or before the threshold' do
      Sync do
        clock = Arcp::FakeClock.new
        runtime = build_runtime(
          agents: { echo: ->(ctx) { ctx.finish(result: nil) } }, clock: clock
        )
        client, server_task = open_pair(runtime)

        old_job = client.submit_job(agent: 'echo')
        clock.advance(60)
        threshold = clock.now.iso8601
        clock.advance(60)
        new_job = client.submit_job(agent: 'echo')

        ids = client.list_jobs(created_after: threshold).to_a.map(&:job_id)
        expect(ids).to include(new_job.job_id)
        expect(ids).not_to include(old_job.job_id)

        client.close
        server_task.stop
      end
    end
  end
end
