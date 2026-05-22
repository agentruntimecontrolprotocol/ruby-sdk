# frozen_string_literal: true

module Arcp
  module Job
    module EventBody
      Status = Data.define(:phase, :message, :fields) do
        def initialize(phase:, message: nil, fields: {})
          super(phase: phase, message: message, fields: fields || {})
        end

        def self.from_h(h)
          h = h.transform_keys(&:to_s)
          new(phase: h.fetch('phase'), message: h['message'], fields: h['fields'] || {})
        end

        def to_h
          out = { 'phase' => phase }
          out['message'] = message if message
          out['fields'] = fields unless fields.empty?
          out
        end
      end
    end
  end
end
