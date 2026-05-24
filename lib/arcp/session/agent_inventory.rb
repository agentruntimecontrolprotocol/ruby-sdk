# frozen_string_literal: true

module Arcp
  module Session
    # One registered agent and its published versions.
    AgentEntry = Data.define(:name, :versions, :default) do
      def self.from_hash(h)
        h = h.transform_keys(&:to_s)
        new(
          name: h.fetch('name'),
          versions: Array(h['versions']).map(&:to_s).freeze,
          default: h['default']
        )
      end

      def to_h
        h = { 'name' => name, 'versions' => versions }
        h['default'] = default if default
        h
      end
    end

    # Ordered registry of the agents advertised during session negotiation.
    AgentInventory = Data.define(:entries) do
      include Enumerable

      def self.from_array(arr)
        new(entries: arr.map { |h| AgentEntry.from_hash(h) }.freeze)
      end

      def each(&) = entries.each(&)
      def to_a = entries.map(&:to_h)

      def find(name) = entries.find { |e| e.name == name }
      def default_for(name) = find(name)&.default
      def versions_for(name) = find(name)&.versions || [].freeze
      def names = entries.map(&:name)

      def resolve(ref)
        name, version = ref.to_s.split('@', 2)
        entry = find(name)
        return nil unless entry

        version ||= entry.default
        return nil unless version

        return nil unless entry.versions.empty? || entry.versions.include?(version)

        "#{name}@#{version}"
      end
    end
  end
end
