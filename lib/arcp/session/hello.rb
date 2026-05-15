# frozen_string_literal: true

module Arcp
  module Session
    Hello = Data.define(:client_name, :client_version, :auth, :capabilities, :resume) do
      def self.from_h(h)
        h = h.transform_keys(&:to_s)
        caps = h['capabilities'] || {}
        new(
          client_name: h['client_name'],
          client_version: h['client_version'],
          auth: h['auth'] || {},
          capabilities: CapabilitySet.new(
            features: Array(caps['features']).freeze,
            encodings: Array(caps['encodings']).freeze,
            agents: nil
          ),
          resume: h['resume']
        )
      end

      def to_h
        h = {
          'client_name' => client_name,
          'client_version' => client_version,
          'auth' => auth,
          'capabilities' => capabilities.to_h.except('agents')
        }
        h['resume'] = resume if resume
        h
      end
    end
  end
end
