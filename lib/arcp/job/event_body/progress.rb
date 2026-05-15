# frozen_string_literal: true

module Arcp
  module Job
    module EventBody
      Progress = Data.define(:current, :total, :units, :message) do
        def self.from_h(h)
          h = h.transform_keys(&:to_s)
          new(
            current: h.fetch('current'),
            total: h['total'],
            units: h['units'],
            message: h['message']
          )
        end

        def to_h
          out = { 'current' => current }
          out['total']   = total if total
          out['units']   = units if units
          out['message'] = message if message
          out
        end
      end
    end
  end
end
