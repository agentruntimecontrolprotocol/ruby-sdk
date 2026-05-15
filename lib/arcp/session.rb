# frozen_string_literal: true

require_relative 'session/feature'
require_relative 'session/capability_set'
require_relative 'session/agent_inventory'
require_relative 'session/hello'
require_relative 'session/welcome'
require_relative 'session/bye'
require_relative 'session/session_error'
require_relative 'session/ping'
require_relative 'session/pong'
require_relative 'session/ack'
require_relative 'session/list_jobs'
require_relative 'session/jobs_response'

module Arcp
  module Session
    # Immutable snapshot of session state after the welcome envelope.
    Info = Data.define(
      :id, :runtime_version, :capabilities, :agents,
      :heartbeat_interval_sec, :resume_token, :resume_window_sec
    ) do
      def supports?(feature) = capabilities.supports?(feature)
    end
  end
end
