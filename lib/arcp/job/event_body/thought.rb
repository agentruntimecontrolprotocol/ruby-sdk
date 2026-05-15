# frozen_string_literal: true

module Arcp
  module Job
    module EventBody
      Thought = Data.define(:text) do
        def self.from_h(h) = new(text: h.transform_keys(&:to_s).fetch('text'))
        def to_h = { 'text' => text }
      end
    end
  end
end
