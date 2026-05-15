# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'job lifecycle', type: :integration do
  it 'submits, streams events, and returns a result' do
    Sync do
      runtime = build_runtime(agents: {
                                echo: lambda { |ctx|
                                  ctx.log(level: 'info', message: 'starting')
                                  ctx.progress(current: 1, total: 1)
                                  ctx.finish(result: { 'echo' => ctx.input })
                                }
                              })
      client, server_task = open_pair(runtime)

      handle = client.submit_job(agent: 'echo', input: { 'msg' => 'hi' })
      expect(handle.agent).to eq('echo@1.0.0')

      events = handle.subscribe(client: client).to_a
      expect(events.map(&:kind)).to eq(%w[log progress])

      result = handle.get_result(client: client)
      expect(result.final_status).to eq('success')
      expect(result.result).to eq('echo' => { 'msg' => 'hi' })

      client.close
      server_task.stop
    end
  end

  it 'surfaces agent errors as JobError exceptions' do
    Sync do
      runtime = build_runtime(agents: {
                                bomb: lambda { |ctx|
                                  ctx.fail!(code: 'PERMISSION_DENIED', message: 'nope', retryable: false)
                                }
                              })
      client, server_task = open_pair(runtime)

      handle = client.submit_job(agent: 'bomb')
      handle.subscribe(client: client).to_a

      expect { handle.get_result(client: client) }.to raise_error(Arcp::Errors::PermissionDenied, /nope/)

      client.close
      server_task.stop
    end
  end
end
