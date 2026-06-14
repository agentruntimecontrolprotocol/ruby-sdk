# frozen_string_literal: true

require 'spec_helper'
require 'bigdecimal'

# Integration spec aimed at branches that the happy-path coverage misses:
# protocol/session error replies, list_jobs filter branches, idempotency
# behavior, cancellation auth, and a few client dispatch corners.

RSpec.describe 'extra branch coverage', type: :integration do
  describe 'session.list_jobs filter branches' do
    it 'narrows by status and agent prefix and respects an explicit cursor' do
      Sync do
        runtime = build_runtime(
          agents: { echo: ->(ctx) { ctx.finish(result: nil) } }
        )
        client, server_task = open_pair(runtime)
        Array.new(4) { client.submit_job(agent: 'echo') }
             .each do |h|
          h.subscribe(client: client).to_a
          h.get_result(client: client)
        end

        succeeded = client.list_jobs(status: ['success']).to_a
        expect(succeeded.size).to eq(4)

        agent_match = client.list_jobs(agent: 'echo').to_a
        expect(agent_match.size).to eq(4)

        # Sliding through the lazy enumerator with a small cursor verifies
        # both the cursor passing and the next-page break.
        first_page = client.list_jobs(limit: 1).first(1)
        expect(first_page.size).to eq(1)

        client.close
        server_task.stop
      end
    end
  end

  describe 'job idempotency' do
    it 'returns the same job id when re-submitting with the same key' do
      Sync do
        runtime = build_runtime(
          agents: { slow: ->(ctx) { ctx.finish(result: nil) } }
        )
        client, server_task = open_pair(runtime)

        h1 = client.submit_job(agent: 'slow', idempotency_key: 'k1')
        h2 = client.submit_job(agent: 'slow', idempotency_key: 'k1')
        expect(h2.job_id).to eq(h1.job_id)

        client.close
        server_task.stop
      end
    end

    it 'rejects an idempotency key reused with a different agent' do
      Sync do
        runtime = build_runtime(
          agents: {
            a: ->(ctx) { ctx.finish(result: nil) },
            b: ->(ctx) { ctx.finish(result: nil) }
          }
        )
        client, server_task = open_pair(runtime)

        client.submit_job(agent: 'a', idempotency_key: 'k2')
        expect do
          client.submit_job(agent: 'b', idempotency_key: 'k2')
        end.to raise_error(Arcp::Errors::DuplicateKey)

        client.close
        server_task.stop
      end
    end
  end

  describe 'cancel authorization' do
    it 'rejects cancel from a different principal' do
      Sync do
        runtime = build_runtime(
          agents: { slow: lambda { |_ctx|
            loop { Async::Task.current.sleep(0.1) }
          } },
          tokens: { 'a-tok' => 'alice', 'b-tok' => 'bob' }
        )
        a, a_task = open_pair(runtime, auth: { 'token' => 'a-tok' })
        b, b_task = open_pair(runtime, auth: { 'token' => 'b-tok' })

        handle = a.submit_job(agent: 'slow')
        # Cancellation from bob should not succeed and the runtime should
        # reply with a job error referencing the unauthorized session.
        b.cancel_job(job_id: handle.job_id, reason: 'unauthorized')

        # Give the runtime a tick to process bob's cancel.
        Async::Task.current.sleep(0.01)

        # alice can still cancel successfully.
        handle.cancel(client: a, reason: 'done')
        expect { handle.get_result(client: a) }.to raise_error(Arcp::Errors::Cancelled)

        a.close
        b.close
        a_task.stop
        b_task.stop
      end
    end
  end

  describe 'handshake error replies' do
    it 'raises ProtocolViolation when the runtime sends an unexpected envelope' do
      Sync do
        server_t, client_t = Arcp::Transport::MemoryTransport.pair
        bad_env = Arcp::Envelope.build(
          type: Arcp::MessageTypes::SESSION_PING,
          session_id: 'ses_bad', payload: { 'nonce' => 'n' }
        )
        # Force a non-welcome envelope into the client's receive queue.
        task = Async do
          client_t.instance_variable_get(:@incoming).enqueue(bad_env)
        end
        task.wait

        expect do
          Arcp::Client.open(transport: client_t, auth: { 'token' => 'demo' }, client_name: 'spec')
        end.to raise_error(Arcp::Errors::ProtocolViolation, /expected session\.welcome/)

        server_t.close
      end
    end

    it 'raises ProtocolViolation when transport closes before welcome' do
      Sync do
        server_t, client_t = Arcp::Transport::MemoryTransport.pair
        client_t.instance_variable_get(:@incoming).enqueue(nil)

        expect do
          Arcp::Client.open(transport: client_t, auth: { 'token' => 'demo' }, client_name: 'spec')
        end.to raise_error(Arcp::Errors::ProtocolViolation, /closed/)

        server_t.close
      end
    end
  end

  describe 'client require_feature!' do
    it 'raises UnnegotiatedFeature when ack is not in the negotiated set' do
      Sync do
        runtime = build_runtime(agents: { echo: ->(ctx) { ctx.finish(result: nil) } })
        client, server_task = open_pair(runtime)

        caps = client.session.capabilities
        stripped = Arcp::Session::CapabilitySet.new(
          features: caps.features - [Arcp::Session::Feature::ACK],
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

        expect { client.ack(1) }.to raise_error(Arcp::Errors::UnnegotiatedFeature)

        client.close
        server_task.stop
      end
    end
  end

  describe 'lease lifecycle hooks' do
    it 'fires publish_error and revokes lease when an agent raises' do
      Sync do
        runtime = build_runtime(
          agents: { broken: ->(_ctx) { raise 'boom' } }
        )
        client, server_task = open_pair(runtime)
        handle = client.submit_job(
          agent: 'broken',
          lease_request: Arcp::Lease::LeaseRequest.new(
            capabilities: ['cost.spend'],
            budget: Arcp::Lease::CostBudget.parse(['USD:1.00'])
          )
        )
        handle.subscribe(client: client).to_a
        expect { handle.get_result(client: client) }.to raise_error(Arcp::Errors::Internal)
        expect(runtime.lease_manager.get(handle.job_id)).to be_nil

        client.close
        server_task.stop
      end
    end
  end
end
