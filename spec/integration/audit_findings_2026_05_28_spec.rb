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
