# frozen_string_literal: true

# stream_resume — long-form writer that pipes GLM-5 streaming deltas through a chunked result.
#
# A long-form writer agent streams a generated article through ARCP's
# chunked-result primitive. The runtime persists every emitted envelope
# in its EventLog under the session's monotonic event_seq, which lets a
# client reconnect after a transport drop and replay the chunks it
# missed (see the companion client.rb for the resume side).
#
# Highlights: §8.4 ctx.stream_result with a per-delta-batch `writer.write`
# and a closing `more: false`; §13.3 / §6.3 the EventLog +
# resume_window_sec wiring that makes the session resumable; GLM-5
# streaming via the OpenAI-compatible z.ai endpoint pipes naturally
# into the chunked stream.

require 'openai'
require_relative '../../samples/_harness'

module StreamResumeRecipe
  HANDLER = lambda do |ctx|
    # GLM-5 via z.ai's OpenAI-compatible API. Swap uri_base for BigModel or
    # another GLM provider; the OpenAI gem shape stays the same.
    glm = OpenAI::Client.new(
      access_token: ENV.fetch('ZAI_API_KEY', 'fake'),
      uri_base: ENV.fetch('ZAI_BASE_URL', 'https://api.z.ai/api/paas/v4/')
    )

    buf = +''
    ctx.stream_result(encoding: 'utf8') do |writer|
      stream = glm.chat(parameters: {
                          model: 'glm-5',
                          stream: proc { |chunk, _bytesize|
                            delta = chunk.dig('choices', 0, 'delta', 'content').to_s
                            next if delta.empty?

                            buf << delta
                            # flush in paragraph-sized batches — one result_chunk
                            # envelope per ~200 chars keeps the seq stream readable
                            # without flooding the EventLog with single-token events
                            if buf.bytesize >= 200
                              writer.write(buf, more: true)
                              buf = +''
                            end
                          },
                          messages: [{
                            role: 'user',
                            content: "Write a 2000-word article on: #{ctx.input['topic']}"
                          }]
                        })
      writer.write(buf, more: false) unless buf.empty?
      _ = stream
    end
    ctx.finish
  end

  def self.runtime
    Harness.runtime(
      agents: { 'long-form' => HANDLER },
      resume_window_sec: 60
    )
  end
end
