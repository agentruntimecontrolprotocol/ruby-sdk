# frozen_string_literal: true

require_relative '../_harness'

module SubscribeSample
  HANDLER = lambda do |ctx|
    3.times do |i|
      ctx.log(level: 'info', message: "step #{i}")
      Async::Task.current.sleep(0.01)
    end
    ctx.finish(result: 'done')
  end

  def self.runtime = Harness.runtime(agents: { 'worker' => HANDLER })
end
