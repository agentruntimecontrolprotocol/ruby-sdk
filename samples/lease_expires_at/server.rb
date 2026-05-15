# frozen_string_literal: true

require 'time'
require_relative '../_harness'

module LeaseExpiresAtSample
  HANDLER = lambda do |ctx|
    # Simulate work; runtime checks lease.expired? via the LeaseManager.
    lm = $arcp_runtime.lease_manager
    lease = lm.get(ctx.job_id)
    if lease&.expired?(Time.now.utc + 120)
      raise Arcp::Errors::LeaseExpired.new("lease expired", details: { 'lease_id' => lease.id })
    end

    ctx.finish(result: 'ok')
  end

  def self.runtime
    r = Harness.runtime(agents: { 'auditor' => HANDLER })
    $arcp_runtime = r
    r
  end
end
