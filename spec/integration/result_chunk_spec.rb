# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'result_chunk streaming', type: :integration do
  it 'streams chunks and terminates with job.result carrying result_id' do
    Sync do
      runtime = build_runtime(agents: {
                                streamer: lambda { |ctx|
                                  ctx.stream_result(encoding: 'utf8') do |writer|
                                    writer.write('hello ', more: true)
                                    writer.write('world', more: false)
                                  end
                                  ctx.finish
                                }
                              })
      client, server_task = open_pair(runtime)
      handle = client.submit_job(agent: 'streamer')
      events = handle.subscribe(client: client).to_a

      chunks = events.select { |e| e.kind == Arcp::Job::EventKind::RESULT_CHUNK }
      expect(chunks.map { |e| e.body.decoded }.join).to eq('hello world')
      expect(chunks.last.body.more).to be(false)

      result = handle.get_result(client: client)
      expect(result.chunked?).to be(true)
      expect(result.result_size).to eq('hello world'.bytesize)

      client.close
      server_task.stop
    end
  end
end
