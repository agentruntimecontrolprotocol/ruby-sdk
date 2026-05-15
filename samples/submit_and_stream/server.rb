# frozen_string_literal: true

require_relative '../_harness'

module SubmitAndStream
  module Server
    HANDLER = lambda do |ctx|
      ctx.log(level: 'info', message: "echoing #{ctx.input.inspect}")
      ctx.progress(current: 1, total: 1, units: 'message')
      ctx.finish(result: { 'echoed' => ctx.input })
    end

    def self.runtime
      Harness.runtime(agents: { 'echo' => HANDLER })
    end
  end
end
