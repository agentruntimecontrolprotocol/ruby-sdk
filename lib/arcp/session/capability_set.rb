# frozen_string_literal: true

module Arcp
  module Session
    CapabilitySet = Data.define(:features, :encodings, :agents) do
      # Session-level serialization encodings (spec §6.2). The wire is JSON;
      # `utf8`/`base64` are result_chunk *data* encodings (§8.4), not session
      # encodings, and must not leak into capability negotiation.
      DEFAULT_ENCODINGS = %w[json].freeze

      def self.local(features: Feature::ALL, encodings: DEFAULT_ENCODINGS, agents: nil)
        new(features: features.dup.freeze, encodings: encodings.dup.freeze, agents: agents)
      end

      def intersect(other)
        self.class.new(
          features: (features & other.features).freeze,
          encodings: (encodings & other.encodings).freeze,
          agents: other.agents || agents
        )
      end

      def supports?(feature) = features.include?(feature)

      def to_h
        h = { 'features' => features, 'encodings' => encodings }
        h['agents'] = agents.to_a if agents
        h
      end
    end
  end
end
