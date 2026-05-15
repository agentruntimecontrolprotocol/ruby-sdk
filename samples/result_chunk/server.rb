# frozen_string_literal: true

require_relative '../_harness'

module ResultChunkSample
  HANDLER = lambda do |ctx|
    ctx.stream_result(encoding: 'utf8') do |writer|
      30.times { |i| writer.write("chunk #{i}\n", more: i < 29) }
    end
    ctx.finish
  end

  def self.runtime = Harness.runtime(agents: { 'streamer' => HANDLER })
end
