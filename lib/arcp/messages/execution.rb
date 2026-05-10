# frozen_string_literal: true

require 'arcp/messages/base'

module Arcp
  module Messages
    # Tool/job execution payloads (§10).
    module Execution
      ToolInvoke   = Arcp::Messages.define('tool.invoke',
                                           required: %i[tool],
                                           optional: { arguments: {} })
      ToolResult   = Arcp::Messages.define('tool.result',
                                           optional: { value: nil, result_ref: nil })
      ToolError    = Arcp::Messages.define('tool.error',
                                           required: %i[code message],
                                           optional: { retryable: false, details: nil, cause: nil,
                                                       trace_id: nil })

      JobAccepted  = Arcp::Messages.define('job.accepted', optional: { detail: nil })
      JobStarted   = Arcp::Messages.define('job.started', optional: { detail: nil })
      JobProgress  = Arcp::Messages.define('job.progress',
                                           optional: { percent: nil, message: nil, detail: nil })
      JobHeartbeat = Arcp::Messages.define('job.heartbeat',
                                           required: %i[sequence],
                                           optional: { deadline_ms: nil, state: 'running' })
      JobCompleted = Arcp::Messages.define('job.completed', optional: { value: nil, result_ref: nil })
      JobFailed    = Arcp::Messages.define('job.failed',
                                           required: %i[code message],
                                           optional: { retryable: false, details: nil })
      JobCancelled = Arcp::Messages.define('job.cancelled',
                                           optional: { reason: nil, code: 'CANCELLED' })
    end
  end
end
