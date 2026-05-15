# frozen_string_literal: true

module Arcp
  module Job
    module EventBody
      Log = Data.define(:level, :message, :fields) do
        def self.from_h(h)
          h = h.transform_keys(&:to_s)
          new(level: h.fetch('level'), message: h.fetch('message'), fields: h['fields'] || {})
        end

        def to_h
          out = { 'level' => level, 'message' => message }
          out['fields'] = fields unless fields.empty?
          out
        end
      end
    end
  end
end
