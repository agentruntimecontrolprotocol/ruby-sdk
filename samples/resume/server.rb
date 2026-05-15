# frozen_string_literal: true

require_relative '../_harness'

module ResumeSample
  HANDLER = ->(ctx) { ctx.log(level: 'info', message: 'hi'); ctx.finish(result: 'ok') }
  def self.runtime = Harness.runtime(agents: { 'echo' => HANDLER })
end
