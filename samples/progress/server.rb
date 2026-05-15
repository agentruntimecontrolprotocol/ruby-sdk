# frozen_string_literal: true

require_relative '../_harness'

module ProgressSample
  HANDLER = lambda do |ctx|
    5.times { |i| ctx.progress(current: i + 1, total: 5, units: 'files') }
    ctx.finish(result: 'done')
  end

  def self.runtime = Harness.runtime(agents: { 'indexer' => HANDLER })
end
