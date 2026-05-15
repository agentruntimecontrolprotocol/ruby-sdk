# frozen_string_literal: true

require_relative '../_harness'

module IdempotentRetrySample
  HANDLER = ->(ctx) { ctx.finish(result: ctx.input) }

  def self.runtime = Harness.runtime(agents: { 'echo' => HANDLER, 'other' => HANDLER })
end
