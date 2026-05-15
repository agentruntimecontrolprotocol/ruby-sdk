# frozen_string_literal: true

module Arcp
  module Job
    module EventBody
      Status = Data.define(:phase, :message) do
        def self.from_h(h)
          h = h.transform_keys(&:to_s)
          new(phase: h.fetch('phase'), message: h['message'])
        end

        def to_h
          out = { 'phase' => phase }
          out['message'] = message if message
          out
        end
      end
    end
  end
end
