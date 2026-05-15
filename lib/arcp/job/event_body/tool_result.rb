# frozen_string_literal: true

module Arcp
  module Job
    module EventBody
      ToolResult = Data.define(:call_id, :result, :error) do
        def self.from_h(h)
          h = h.transform_keys(&:to_s)
          new(call_id: h.fetch('call_id'), result: h['result'], error: h['error'])
        end

        def to_h
          out = { 'call_id' => call_id }
          out['result'] = result if result
          out['error']  = error if error
          out
        end

        def ok? = error.nil?
      end
    end
  end
end
