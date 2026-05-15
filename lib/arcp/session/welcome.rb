# frozen_string_literal: true

module Arcp
  module Session
    Welcome = Data.define(
      :runtime_name, :runtime_version, :capabilities,
      :heartbeat_interval_sec, :resume_token, :resume_window_sec
    ) do
      def self.from_h(h)
        h = h.transform_keys(&:to_s)
        caps = h['capabilities'] || {}
        new(
          runtime_name: h['runtime_name'],
          runtime_version: h['runtime_version'],
          capabilities: CapabilitySet.new(
            features: Array(caps['features']).freeze,
            encodings: Array(caps['encodings']).freeze,
            agents: caps['agents'] ? AgentInventory.from_array(caps['agents']) : nil
          ),
          heartbeat_interval_sec: h['heartbeat_interval_sec'],
          resume_token: h['resume_token'],
          resume_window_sec: h['resume_window_sec']
        )
      end

      def to_h
        {
          'runtime_name' => runtime_name,
          'runtime_version' => runtime_version,
          'capabilities' => capabilities.to_h,
          'heartbeat_interval_sec' => heartbeat_interval_sec,
          'resume_token' => resume_token,
          'resume_window_sec' => resume_window_sec
        }
      end
    end
  end
end
