# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'job cancellation', type: :integration do
  it 'cancels a running job and yields final_status: cancelled' do
    Sync do
      runtime = build_runtime(agents: {
                                sleepy: ->(ctx) {
                                  ctx.progress(current: 0, total: 10)
                                  Async::Task.current.sleep(5)
                                  ctx.finish
                                }
                              })
      client, server_task = open_pair(runtime)
      handle = client.submit_job(agent: 'sleepy')

      Async::Task.current.sleep(0.05)
      handle.cancel(client: client, reason: 'user request')

      expect { handle.get_result(client: client) }.to raise_error(Arcp::Errors::Cancelled)
      client.close
      server_task.stop
    end
  end
end
