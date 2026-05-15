# frozen_string_literal: true

module Arcp
  module Job
    module EventBody
      ToolCall = Data.define(:call_id, :tool, :args) do
        def self.from_h(h)
          h = h.transform_keys(&:to_s)
          new(call_id: h.fetch('call_id'), tool: h.fetch('tool'), args: h['args'] || {})
        end

        def to_h = { 'call_id' => call_id, 'tool' => tool, 'args' => args }
      end
    end
  end
end
