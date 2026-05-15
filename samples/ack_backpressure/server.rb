# frozen_string_literal: true

require_relative '../_harness'

module AckBackpressureSample
  HANDLER = lambda do |ctx|
    20.times { |i| ctx.progress(current: i + 1, total: 20) }
    ctx.finish(result: 'done')
  end

  def self.runtime = Harness.runtime(agents: { 'producer' => HANDLER })
end
