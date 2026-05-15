# frozen_string_literal: true

require 'bigdecimal'
require_relative '../_harness'

module CostBudgetSample
  HANDLER = lambda do |ctx|
    lm = $arcp_runtime.lease_manager
    [BigDecimal('0.42'), BigDecimal('0.70'), BigDecimal('0.05')].each do |amount|
      ctx.metric(name: 'cost.search', value: amount.to_s('F'), unit: 'USD')
      lm.try_spend!(ctx.job_id, 'USD', amount)
    end
    ctx.finish(result: 'spent')
  end

  def self.runtime
    r = Harness.runtime(agents: { 'shopper' => HANDLER })
    $arcp_runtime = r
    r
  end
end
