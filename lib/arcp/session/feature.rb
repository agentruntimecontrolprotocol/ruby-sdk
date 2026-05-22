# frozen_string_literal: true

module Arcp
  module Session
    module Feature
      HEARTBEAT        = 'heartbeat'
      ACK              = 'ack'
      LIST_JOBS        = 'list_jobs'
      SUBSCRIBE        = 'subscribe'
      LEASE_EXPIRES_AT = 'lease_expires_at'
      COST_BUDGET      = 'cost.budget'
      PROGRESS         = 'progress'
      RESULT_CHUNK     = 'result_chunk'
      AGENT_VERSIONS   = 'agent_versions'
      MODEL_USE        = 'model.use'
      PROVISIONED_CREDENTIALS = 'provisioned_credentials'

      ALL = [
        HEARTBEAT, ACK, LIST_JOBS, SUBSCRIBE, LEASE_EXPIRES_AT,
        COST_BUDGET, PROGRESS, RESULT_CHUNK, AGENT_VERSIONS,
        MODEL_USE, PROVISIONED_CREDENTIALS
      ].freeze
    end
  end
end
