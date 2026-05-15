# frozen_string_literal: true

require_relative '../_harness'

module AgentVersionsSample
  def self.runtime
    handler = ->(ctx) { ctx.finish(result: ctx.agent) }
    r = Harness.runtime(
      agents: {
        'code-refactor' => { handler: handler, versions: %w[1.0.0 2.0.0], default: '2.0.0' }
      }
    )
    r
  end
end
