# frozen_string_literal: true

require 'time'
require 'bigdecimal'
require_relative '../_harness'

module DelegateSample
  PARENT = lambda do |ctx|
    parent_lease = $arcp_runtime.lease_manager.get(ctx.job_id)
    child_request = Arcp::Lease::LeaseRequest.new(
      capabilities: ['compute.read'],
      budget: Arcp::Lease::CostBudget.parse(['USD:1.00']),
      expires_at: nil
    )
    child_lease = Arcp::Lease::Subsetting.bound(parent: parent_lease, request: child_request)

    ctx.emit(
      kind: Arcp::Job::EventKind::DELEGATE,
      body: Arcp::Job::EventBody::Delegate.new(
        child_job_id: "child_#{ctx.job_id}",
        agent: 'child', lease: child_lease
      )
    )
    ctx.finish(result: 'delegated')
  end

  def self.runtime
    r = Harness.runtime(agents: { 'parent' => PARENT })
    $arcp_runtime = r
    r
  end
end
