# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'provisioned credentials', type: :integration do
  it 'attaches credentials to job.accepted and client handles' do
    Sync do
      provisioner = Arcp::Credentials::InMemoryProvisioner.new
      runtime = build_runtime(
        agents: { echo: ->(ctx) { ctx.finish(result: ctx.input) } },
        credential_provisioner: provisioner
      )
      client, server_task = open_pair(runtime)

      handle = client.submit_job(agent: 'echo', input: { 'ok' => true })

      expect(handle.credentials.first.value).to eq("sk-test-#{handle.job_id}")
      expect(handle.credential_for(endpoint: 'https://gateway.test/v1').scheme).to eq('bearer')
      handle.get_result(client: client)
      client.close
      server_task.stop
    end
  end

  it 'revokes credentials on success' do
    Sync do
      provisioner = Arcp::Credentials::InMemoryProvisioner.new
      runtime = build_runtime(
        agents: { echo: ->(ctx) { ctx.finish(result: 'ok') } },
        credential_provisioner: provisioner
      )
      client, server_task = open_pair(runtime)

      handle = client.submit_job(agent: 'echo')
      handle.get_result(client: client)

      expect(provisioner.revoked).to include("cred_#{handle.job_id}_0")
      client.close
      server_task.stop
    end
  end

  it 'revokes credentials on error' do
    Sync do
      provisioner = Arcp::Credentials::InMemoryProvisioner.new
      runtime = build_runtime(
        agents: { failer: ->(ctx) { ctx.fail!(code: 'INTERNAL_ERROR') } },
        credential_provisioner: provisioner
      )
      client, server_task = open_pair(runtime)

      handle = client.submit_job(agent: 'failer')
      expect { handle.get_result(client: client) }.to raise_error(Arcp::Errors::Internal)

      expect(provisioner.revoked).to include("cred_#{handle.job_id}_0")
      client.close
      server_task.stop
    end
  end

  it 'revokes credentials on cancellation' do
    Sync do
      provisioner = Arcp::Credentials::InMemoryProvisioner.new
      runtime = build_runtime(
        agents: { sleepy: ->(_ctx) { Async::Task.current.sleep(5) } },
        credential_provisioner: provisioner
      )
      client, server_task = open_pair(runtime)

      handle = client.submit_job(agent: 'sleepy')
      Async::Task.current.sleep(0.05)
      handle.cancel(client: client, reason: 'stop')
      expect { handle.get_result(client: client) }.to raise_error(Arcp::Errors::Cancelled)

      expect(provisioner.revoked).to include("cred_#{handle.job_id}_0")
      client.close
      server_task.stop
    end
  end

  it 'revokes credentials on timeout' do
    Sync do
      provisioner = Arcp::Credentials::InMemoryProvisioner.new
      runtime = build_runtime(
        agents: { sleepy: ->(_ctx) { Async::Task.current.sleep(5) } },
        credential_provisioner: provisioner
      )
      client, server_task = open_pair(runtime)

      handle = client.submit_job(agent: 'sleepy', max_runtime_sec: 0.01)
      expect { handle.get_result(client: client) }.to raise_error(Arcp::Errors::Timeout)

      expect(provisioner.revoked).to include("cred_#{handle.job_id}_0")
      client.close
      server_task.stop
    end
  end

  it 'emits credential rotation status and revokes the prior id' do
    Sync do
      provisioner = Arcp::Credentials::InMemoryProvisioner.new
      runtime = build_runtime(
        agents: { rotator: lambda { |ctx|
          Async::Task.current.sleep(0.05)
          ctx.rotate_credential(id: "cred_#{ctx.job_id}_0", new_value: 'sk-rotated')
          ctx.finish(result: 'rotated')
        } },
        credential_provisioner: provisioner
      )
      client, server_task = open_pair(runtime)

      handle = client.submit_job(agent: 'rotator')
      events = handle.subscribe(client: client).to_a
      event = events.find { |item| item.body.respond_to?(:phase) && item.body.phase == 'credential_rotated' }

      expect(event.body.fields['value']).to eq('sk-rotated')
      expect(provisioner.revoked).to include("cred_#{handle.job_id}_0")
      client.close
      server_task.stop
    end
  end

  it 'does not expose credentials through list_jobs' do
    Sync do
      provisioner = Arcp::Credentials::InMemoryProvisioner.new
      runtime = build_runtime(
        agents: { echo: ->(ctx) { ctx.finish(result: 'ok') } },
        credential_provisioner: provisioner
      )
      client, server_task = open_pair(runtime)

      handle = client.submit_job(agent: 'echo')
      handle.get_result(client: client)
      summary = client.list_jobs.to_a.first

      expect(summary.to_h).not_to have_key('credentials')
      client.close
      server_task.stop
    end
  end
end
