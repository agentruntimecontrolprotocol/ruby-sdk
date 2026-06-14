# frozen_string_literal: true

module Arcp
  module Job
    module EventBody
      Progress = Data.define(:current, :total, :units, :message) do
        # Spec §8.2.1: `current` MUST be a non-negative number. A negative
        # value is rejected with INVALID_REQUEST at construction so it can
        # never be emitted on the wire.
        def initialize(current:, total: nil, units: nil, message: nil)
          if current.nil? || !current.is_a?(Numeric) || current.negative?
            raise Arcp::Errors::InvalidRequest,
                  "progress.current must be a non-negative number: #{current.inspect}"
          end

          super
        end

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
