# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'model.use enforcement', type: :integration do
  it 'rejects models outside model.use' do
    Sync do
      runtime = build_runtime(
        agents: { llm: lambda { |ctx|
          runtime.lease_manager.check_model!(ctx.job_id, model_id: 'anthropic/claude-3-opus')
          ctx.finish(result: 'ok')
        } }
      )
      client, server_task = open_pair(runtime)

      handle = client.submit_job(agent: 'llm', lease_request: model_lease(['tier-fast/*']))

      expect { handle.get_result(client: client) }.to raise_error(Arcp::Errors::PermissionDenied)
      client.close
      server_task.stop
    end
  end

  it 'admits models matching model.use' do
    Sync do
      runtime = build_runtime(
        agents: { llm: lambda { |ctx|
          runtime.lease_manager.check_model!(ctx.job_id, model_id: 'tier-fast/gpt-4o-mini')
          ctx.finish(result: 'ok')
        } }
      )
      client, server_task = open_pair(runtime)

      handle = client.submit_job(agent: 'llm', lease_request: model_lease(['tier-fast/*']))

      expect(handle.get_result(client: client).result).to eq('ok')
      client.close
      server_task.stop
    end
  end

  def model_lease(patterns)
    Arcp::Lease::LeaseRequest.new(
      capabilities: ['model.call'],
      model_use: patterns
    )
  end
end
