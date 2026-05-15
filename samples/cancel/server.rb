# frozen_string_literal: true

require_relative '../_harness'

module CancelSample
  HANDLER = lambda do |ctx|
    ctx.progress(current: 0, total: 100)
    Async::Task.current.sleep(5)
    ctx.finish
  end

  def self.runtime = Harness.runtime(agents: { 'sleepy' => HANDLER })
end
