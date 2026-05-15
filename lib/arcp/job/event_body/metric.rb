# frozen_string_literal: true

module Arcp
  module Job
    module EventBody
      Metric = Data.define(:name, :value, :unit) do
        def self.from_h(h)
          h = h.transform_keys(&:to_s)
          new(name: h.fetch('name'), value: h.fetch('value'), unit: h['unit'])
        end

        def to_h
          out = { 'name' => name, 'value' => value }
          out['unit'] = unit if unit
          out
        end
      end
    end
  end
end
