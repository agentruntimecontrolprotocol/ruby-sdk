# frozen_string_literal: true

require_relative '../_harness'

module LeaseViolationSample
  HANDLER = lambda do |ctx|
    lm = $arcp_runtime.lease_manager
    begin
      lm.check!(ctx.job_id, capability: 'fs.write')
    rescue Arcp::Errors::PermissionDenied => e
      ctx.tool_result(call_id: 'fs1', error: e.to_payload)
    end
    ctx.finish(result: 'continued')
  end

  def self.runtime
    r = Harness.runtime(agents: { 'auditor' => HANDLER })
    $arcp_runtime = r
    r
  end
end
