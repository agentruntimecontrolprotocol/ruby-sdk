# frozen_string_literal: true

# multi_agent_budget — planner decomposes a question and delegates workers under a shared cap.
#
# A research planner with a USD:0.50 budget decomposes a question and
# delegates sub-questions to worker children. Each grant is sliced from
# the planner's own remaining budget, so the cap effectively cascades
# across the tree. Workers that overspend trip BudgetExhausted; the
# planner skips sub-questions that no longer fit.
#
# Highlights: §13.2 delegation + lease-subset enforcement at delegate
# time, §9.6 cost.budget auto-decrement via metrics, and the
# "debit-self-for-each-grant" pattern that turns ARCP's independent
# per-job counters into a shared cascade.

require 'bigdecimal'
require 'json'
require 'openai'
require_relative '../../samples/_harness'

module MultiAgentBudgetRecipe
  PHASES = %w[gather analyze summarize].freeze
  GRANT_BY_DEPTH = {
    1 => BigDecimal('0.05'),
    2 => BigDecimal('0.10'),
    3 => BigDecimal('0.15')
  }.freeze

  PLANNER = lambda do |ctx|
    lm = $arcp_runtime.lease_manager
    openai = OpenAI::Client.new

    # decompose the question into sub-questions tagged with a depth score
    plan = openai.chat(
      parameters: {
        model: 'gpt-4o-mini',
        response_format: { type: 'json_object' },
        messages: [{
          role: 'user',
          content: 'Decompose into 5 sub-questions. JSON ' \
                   '{subQuestions:[{question,depth:1|2|3}]}. ' \
                   "Q: #{ctx.input['question']}"
        }]
      }
    )
    # charge the plan call against our own budget so the next subset check
    # (below, at each delegate) sees an honest "remaining"
    ctx.metric(name: 'cost.completion', value: '0.05', unit: 'USD')
    lm.try_spend!(ctx.job_id, 'USD', BigDecimal('0.05'))
    sub_questions = JSON.parse(plan.dig('choices', 0, 'message', 'content'))['subQuestions']

    delegated = []
    dropped = []
    sub_questions.each_with_index do |sq, i|
      grant = GRANT_BY_DEPTH[sq['depth']] || BigDecimal('0.05')
      # skip if our remaining budget no longer fits this grant — the runtime
      # would reject it anyway via Subsetting.bound, but a graceful pre-check
      # gives the planner a chance to report it back
      remaining = lm.remaining(ctx.job_id)['USD'] || BigDecimal('0')
      if remaining < grant
        dropped << { 'question' => sq['question'], 'reason' => 'budget' }
        next
      end

      child_id = "child_#{ctx.job_id}_#{i}"
      child_request = Arcp::Lease::LeaseRequest.new(
        capabilities: ['tool.call:llm.complete'],
        budget: Arcp::Lease::CostBudget.parse(["USD:#{format('%.2f', grant)}"]),
        model_use: nil,
        expires_at: nil
      )
      child_lease = Arcp::Lease::Subsetting.bound(
        parent: lm.get(ctx.job_id), request: child_request
      )

      ctx.emit(
        kind: Arcp::Job::EventKind::DELEGATE,
        body: Arcp::Job::EventBody::Delegate.new(
          child_job_id: child_id, agent: 'worker', lease: child_lease
        )
      )
      delegated << { 'question' => sq['question'], 'grant' => "USD:#{format('%.2f', grant)}" }

      # debit ourselves so the next iteration's pre-check (and the runtime's
      # subset check) reflect what we've already committed
      ctx.metric(name: 'cost.delegate', value: grant.to_s('F'), unit: 'USD')
      lm.try_spend!(ctx.job_id, 'USD', grant)
    end

    ctx.finish(result: { 'plan' => sub_questions, 'delegated' => delegated, 'dropped' => dropped })
  end

  WORKER = lambda do |ctx|
    lm = $arcp_runtime.lease_manager
    openai = OpenAI::Client.new

    # three phases against the worker's own per-job budget
    PHASES.each do |phase|
      openai.chat(parameters: {
                    model: 'gpt-4o-mini',
                    messages: [{ role: 'user', content: "#{phase}: #{ctx.input['question']}" }]
                  })
      ctx.metric(name: 'cost.completion', value: '0.05', unit: 'USD')
      # try_spend! raises BudgetExhausted once the counter would go negative —
      # the runtime converts the raise into a terminal job.error.
      lm.try_spend!(ctx.job_id, 'USD', BigDecimal('0.05'))
    end

    ctx.finish(result: { 'phases' => PHASES })
  end

  def self.runtime
    r = Harness.runtime(agents: { 'planner' => PLANNER, 'worker' => WORKER })
    $arcp_runtime = r
    r
  end
end
