# frozen_string_literal: true

# stream_resume client — submit the writer, observe streamed chunks, capture
# the resume token so a follow-up session could replay the tail after a drop.
#
# A full mid-stream resume across separate processes lives in
# spec/integration/. In this in-process demo we drive the streaming
# shape end-to-end and surface the resume_token + last seen seq so a
# new client could reconnect via `Arcp::Client.open(resume: ...)`.

require_relative '../../samples/_harness'

module StreamResumeRecipe
  module Client
    def self.run(client)
      handle = client.submit_job(
        agent: 'long-form',
        input: { 'topic' => 'urban heat islands' }
      )
      chunks = {}
      handle.subscribe(client: client).each do |event|
        next unless event.kind == Arcp::Job::EventKind::RESULT_CHUNK

        # dict dedup is what handles a real resume boundary — if session 1 saw
        # chunk_seq 3 and the runtime later replays 3 again, the second write
        # just overwrites.
        chunks[event.body.chunk_seq] = event.body.decoded
      end
      result = handle.get_result(client: client)
      assembled = chunks.sort_by(&:first).map(&:last).join
      [handle, chunks, assembled, result]
    end
  end
end
