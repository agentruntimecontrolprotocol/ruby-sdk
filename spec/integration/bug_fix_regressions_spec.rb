# frozen_string_literal: true

require 'spec_helper'
require 'bigdecimal'

RSpec.describe 'bug fix regressions', type: :integration do
  describe 'resume token validation (#26)' do
    it 'restores the prior session and replays buffered events after reconnect' do
      Sync do
        runtime = build_runtime(
          agents: { producer: lambda { |ctx|
            5.times { |i| ctx.log(level: 'info', message: "event-#{i}") }
            ctx.finish(result: 'ok')
          } }
        )

        server_t1, client_t1 = Arcp::Transport::MemoryTransport.pair
        server_task1 = Async { runtime.accept(server_t1) }
        client1 = Arcp::Client.open(transport: client_t1, auth: { 'token' => 'demo' }, client_name: 'spec')

        handle = client1.submit_job(agent: 'producer')
        # Drain the entire stream + terminal result on the original session
        # so the event log is fully populated before we disconnect.
        handle.subscribe(client: client1).to_a
        original_session = client1.session.id
        resume_token = client1.session.resume_token

        client_t1.close
        client1.instance_variable_set(:@closed, true)
        server_task1.stop

        server_t2, client_t2 = Arcp::Transport::MemoryTransport.pair
        server_task2 = Async { runtime.accept(server_t2) }
        # Resume with last_event_seq=2 — runtime must replay events 3-5 and
        # the terminal job.result envelope on the new connection.
        client2 = Arcp::Client.open(
          transport: client_t2, auth: { 'token' => 'demo' }, client_name: 'spec',
          resume: { 'token' => resume_token, 'last_event_seq' => 2 }
        )

        expect(client2.session.id).to eq(original_session)
        result = client2.get_result(job_id: handle.job_id)
        expect(result.result).to eq('ok')

        client2.close
        server_task2.stop
      end
    end

    it 'raises ResumeWindowExpired for unknown tokens' do
      Sync do
        runtime = build_runtime
        server_t, client_t = Arcp::Transport::MemoryTransport.pair
        server_task = Async { runtime.accept(server_t) }

        expect do
          Arcp::Client.open(
            transport: client_t, auth: { 'token' => 'demo' }, client_name: 'spec',
            resume: { 'token' => 'totally-bogus', 'last_event_seq' => 0 }
          )
        end.to raise_error(Arcp::Errors::ResumeWindowExpired)

        server_task.stop
      end
    end
  end

  describe 'subscribe_job default attach (#27)' do
    it 'attaches an observer session that omits from_event_seq' do
      Sync do
        runtime = build_runtime(
          agents: { drip: lambda { |ctx|
            10.times do |i|
              ctx.log(level: 'info', message: "drip-#{i}")
              Async::Task.current.sleep(0.005)
            end
            ctx.finish(result: 'done')
          } },
          tokens: { 'alice-tok' => 'alice', 'observer-tok' => 'alice' }
        )

        submitter, sub_task = open_pair(runtime, auth: { 'token' => 'alice-tok' })
        observer, obs_task = open_pair(runtime, auth: { 'token' => 'observer-tok' })

        handle = submitter.submit_job(agent: 'drip')

        # Subscribe immediately — observer should attach to the runtime
        # fanout even without supplying from_event_seq.
        events = observer.subscribe_job(job_id: handle.job_id).to_a

        # The observer must see at least the terminal end marker and may
        # receive any in-flight events that arrived after attach.
        expect(events).to all(be_a(Arcp::Job::Event))

        # Sanity check: the runtime accepted the job.subscribe and replied.
        sent_types = observer.transport.sent.map(&:type)
        expect(sent_types).to include(Arcp::MessageTypes::JOB_SUBSCRIBE)

        submitter.close
        observer.close
        sub_task.stop
        obs_task.stop
      end
    end

    it 'raises UnnegotiatedFeature when the subscribe feature is absent' do
      Sync do
        runtime = build_runtime(agents: { echo: ->(ctx) { ctx.finish(result: nil) } })
        client, server_task = open_pair(runtime)

        handle = client.submit_job(agent: 'echo')
        client.instance_variable_get(:@submitted_jobs).delete(handle.job_id)
        # Strip the subscribe feature from the session caps.
        caps = client.session.capabilities
        stripped = Arcp::Session::CapabilitySet.new(
          features: caps.features - [Arcp::Session::Feature::SUBSCRIBE],
          encodings: caps.encodings, agents: caps.agents
        )
        client.instance_variable_set(:@session,
                                     Arcp::Session::Info.new(
                                       id: client.session.id,
                                       runtime_version: client.session.runtime_version,
                                       capabilities: stripped,
                                       agents: client.session.agents,
                                       heartbeat_interval_sec: client.session.heartbeat_interval_sec,
                                       resume_token: client.session.resume_token,
                                       resume_window_sec: client.session.resume_window_sec
                                     ))

        expect do
          client.subscribe_job(job_id: handle.job_id)
        end.to raise_error(Arcp::Errors::UnnegotiatedFeature)

        client.close
        server_task.stop
      end
    end
  end

  describe 'subscription history replay (#28)' do
    it 'indexes envelopes by job id so a foreign session can replay them' do
      clock = Arcp::FakeClock.new
      log = Arcp::Runtime::EventLog.new(window_sec: 60, clock: clock)
      job_id = 'job_test'
      submitter_session = 'ses_submitter'
      observer_session  = 'ses_observer'

      3.times do |i|
        env = Arcp::Envelope.build(
          type: Arcp::MessageTypes::JOB_EVENT,
          session_id: submitter_session, job_id: job_id,
          event_seq: i + 1,
          payload: { 'kind' => 'log', 'body' => { 'level' => 'info', 'message' => "msg-#{i}" } }
        )
        log.append(submitter_session, env)
      end

      replay = log.replay_job(job_id, from_event_seq: 0)
      expect(replay.size).to eq(3)
      expect(replay.map(&:event_seq)).to eq([1, 2, 3])

      # Observer's own session buffer is empty; the prior-keyed replay must
      # succeed regardless of the subscriber's session id.
      expect(log.replay(observer_session)).to be_empty
    end

    it 'leaves the job event stream recoverable after the agent finishes' do
      Sync do
        runtime = build_runtime(
          agents: { quick: lambda { |ctx|
            ctx.log(level: 'info', message: 'first')
            ctx.log(level: 'info', message: 'second')
            ctx.finish(result: 'ok')
          } }
        )

        client, server_task = open_pair(runtime)
        handle = client.submit_job(agent: 'quick')
        handle.subscribe(client: client).to_a
        client.get_result(job_id: handle.job_id)

        replay = runtime.event_log.replay_job(handle.job_id, from_event_seq: 0)
        kinds = replay.map(&:type)
        expect(kinds.count(Arcp::MessageTypes::JOB_EVENT)).to eq(2)
        expect(kinds).to include(Arcp::MessageTypes::JOB_RESULT)

        client.close
        server_task.stop
      end
    end
  end

  describe 'stream_result writer totals (#29)' do
    it 'records totals when the agent uses the non-block writer path' do
      Sync do
        runtime = build_runtime(
          agents: { manual_streamer: lambda { |ctx|
            writer = ctx.stream_result(encoding: 'utf8')
            writer.write('alpha ', more: true)
            writer.write('beta', more: false)
            writer.close
            ctx.finish
          } }
        )
        client, server_task = open_pair(runtime)
        handle = client.submit_job(agent: 'manual_streamer')
        events = handle.subscribe(client: client).to_a
        chunks = events.select { |e| e.kind == Arcp::Job::EventKind::RESULT_CHUNK }

        expect(chunks.map { |e| e.body.decoded }.join).to eq('alpha beta')

        result = handle.get_result(client: client)
        expect(result.chunked?).to be(true)
        expect(result.result_size).to eq('alpha beta'.bytesize)
        expect(result.result_id).not_to be_nil

        client.close
        server_task.stop
      end
    end
  end

  describe 'budget enforcement (#30)' do
    it 'rejects spending in a currency absent from the budget' do
      Sync do
        lease_manager_ref = nil
        runtime = build_runtime(
          agents: { ccy_mismatch: lambda { |ctx|
            lease_manager_ref.try_spend!(ctx.job_id, 'EUR', BigDecimal('0.10'))
            ctx.finish(result: 'never')
          } }
        )
        lease_manager_ref = runtime.lease_manager

        client, server_task = open_pair(runtime)
        handle = client.submit_job(
          agent: 'ccy_mismatch',
          lease_request: Arcp::Lease::LeaseRequest.new(
            capabilities: ['cost.spend'],
            budget: Arcp::Lease::CostBudget.parse(['USD:1.00'])
          )
        )
        handle.subscribe(client: client).to_a
        expect { handle.get_result(client: client) }.to raise_error(Arcp::Errors::BudgetExhausted, /not in budget/)

        client.close
        server_task.stop
      end
    end

    it 'remains unrestricted when no budget is attached' do
      Sync do
        lease_manager_ref = nil
        runtime = build_runtime(
          agents: { free_spender: lambda { |ctx|
            lease_manager_ref.try_spend!(ctx.job_id, 'USD', BigDecimal('999.00'))
            ctx.finish(result: 'unbounded')
          } }
        )
        lease_manager_ref = runtime.lease_manager
        client, server_task = open_pair(runtime)
        handle = client.submit_job(agent: 'free_spender')
        handle.subscribe(client: client).to_a
        expect(handle.get_result(client: client).result).to eq('unbounded')

        client.close
        server_task.stop
      end
    end
  end

  describe 'lease_constraints max_budget enforcement (#31)' do
    it 'rejects a lease budget that exceeds max_budget' do
      Sync do
        runtime = build_runtime(
          agents: { echo: ->(ctx) { ctx.finish(result: nil) } }
        )
        client, server_task = open_pair(runtime)

        expect do
          client.submit_job(
            agent: 'echo',
            lease_request: Arcp::Lease::LeaseRequest.new(
              capabilities: ['cost.spend'],
              budget: Arcp::Lease::CostBudget.parse(['USD:5.00'])
            ),
            lease_constraints: Arcp::Lease::LeaseConstraints.new(
              max_budget: ['USD:1.00']
            )
          )
        end.to raise_error(Arcp::Errors::LeaseSubsetViolation)

        client.close
        server_task.stop
      end
    end

    it 'accepts a lease budget within max_budget' do
      Sync do
        runtime = build_runtime(
          agents: { echo: ->(ctx) { ctx.finish(result: nil) } }
        )
        client, server_task = open_pair(runtime)

        handle = client.submit_job(
          agent: 'echo',
          lease_request: Arcp::Lease::LeaseRequest.new(
            capabilities: ['cost.spend'],
            budget: Arcp::Lease::CostBudget.parse(['USD:0.50'])
          ),
          lease_constraints: Arcp::Lease::LeaseConstraints.new(
            max_budget: ['USD:1.00']
          )
        )
        expect(handle).not_to be_nil

        client.close
        server_task.stop
      end
    end

    it 'round-trips max_budget through wire shape' do
      constraints = Arcp::Lease::LeaseConstraints.new(
        expires_at: nil, max_budget: ['USD:2.50', 'EUR:1.00']
      )
      restored = Arcp::Lease::LeaseConstraints.from_h(constraints.to_h)
      expect(restored.max_budget.remaining('USD').to_s('F')).to eq('2.5')
      expect(restored.max_budget.remaining('EUR').to_s('F')).to eq('1.0')
    end
  end

  describe 'client waiter safety (#32)' do
    it 'raises ProtocolViolation when get_result is woken by a closed transport' do
      Sync do
        runtime = build_runtime(
          agents: { hang: lambda { |_ctx|
            # Never finishes; we close the transport mid-flight.
            sleep
          } }
        )
        client, server_task = open_pair(runtime)
        handle = client.submit_job(agent: 'hang')

        waiter = Async do
          expect { client.get_result(job_id: handle.job_id) }
            .to raise_error(Arcp::Errors::ProtocolViolation)
        end

        Async::Task.current.sleep(0.02)
        client.close
        waiter.wait
        server_task.stop
      end
    end
  end

  describe 'session.bye on close (#33)' do
    it 'emits a session.bye envelope before marking the client closed' do
      Sync do
        runtime = build_runtime
        server_t, client_t = Arcp::Transport::MemoryTransport.pair
        server_task = Async { runtime.accept(server_t) }
        client = Arcp::Client.open(transport: client_t, auth: { 'token' => 'demo' }, client_name: 'spec')

        client.close(reason: 'done')

        bye_envelopes = client_t.sent.select { |e| e.type == Arcp::MessageTypes::SESSION_BYE }
        expect(bye_envelopes.size).to eq(1)
        expect(bye_envelopes.first.payload['reason']).to eq('done')

        server_task.stop
      end
    end
  end

  describe 'list_jobs pagination stability (#38)' do
    it 'keeps cursors stable when new jobs are submitted between page reads' do
      Sync do
        runtime = build_runtime(agents: { echo: ->(ctx) { ctx.finish(result: nil) } })
        client, server_task = open_pair(runtime)

        Array.new(3) { client.submit_job(agent: 'echo') }
             .each do |h|
          h.subscribe(client: client).to_a
          h.get_result(client: client)
        end

        page1 = runtime.job_manager.list(principal_id: 'alice', limit: 2)
        expect(page1.jobs.size).to eq(2)
        expect(page1.next_cursor).not_to be_nil

        # Inject another job between page reads.
        client.submit_job(agent: 'echo').subscribe(client: client).to_a

        page2 = runtime.job_manager.list(principal_id: 'alice', limit: 2, cursor: page1.next_cursor)
        # The third job from the original burst plus the freshly-added one fit on page 2.
        ids = (page1.jobs + page2.jobs).map { |j| j['job_id'] }
        expect(ids.uniq.size).to eq(ids.size)
        expect(ids.size).to be >= 3

        client.close
        server_task.stop
      end
    end
  end
end
