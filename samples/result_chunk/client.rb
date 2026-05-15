# frozen_string_literal: true

require_relative '../_harness'

module ResultChunkSample
  module Client
    def self.run(client)
      handle = client.submit_job(agent: 'streamer')
      events = handle.subscribe(client: client).to_a
      chunks = events.select { _1.kind == Arcp::Job::EventKind::RESULT_CHUNK }
      assembled = chunks.map { _1.body.decoded }.join
      result = handle.get_result(client: client)
      [handle, chunks, assembled, result]
    end
  end
end
