# frozen_string_literal: true

require_relative '../_harness'

module ListJobsSample
  HANDLER = ->(ctx) { ctx.finish(result: 'ok') }

  def self.runtime
    Harness.runtime(agents: { 'echo' => HANDLER, 'sleeper' => HANDLER })
  end
end
