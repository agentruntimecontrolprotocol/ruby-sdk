# frozen_string_literal: true

module Arcp
  module Job
    module EventBody
      TraceSpan = Data.define(:span_id, :parent_span_id, :name, :start_at, :end_at, :attributes) do
        def self.from_h(h)
          h = h.transform_keys(&:to_s)
          new(
            span_id: h.fetch('span_id'),
            parent_span_id: h['parent_span_id'],
            name: h.fetch('name'),
            start_at: h['start_at'],
            end_at: h['end_at'],
            attributes: h['attributes'] || {}
          )
        end

        def to_h
          out = { 'span_id' => span_id, 'name' => name }
          out['parent_span_id'] = parent_span_id if parent_span_id
          out['start_at']       = start_at if start_at
          out['end_at']         = end_at if end_at
          out['attributes']     = attributes unless attributes.empty?
          out
        end
      end
    end
  end
end
