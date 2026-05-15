# frozen_string_literal: true

module Arcp
  module Job
    AgentRef = Data.define(:name, :version) do
      def self.parse(ref)
        return nil if ref.nil?

        name, version = ref.to_s.split('@', 2)
        raise Arcp::Errors::InvalidRequest, "agent name must be non-empty" if name.nil? || name.empty?

        new(name: name, version: version)
      end

      def to_s = version ? "#{name}@#{version}" : name
    end
  end
end
