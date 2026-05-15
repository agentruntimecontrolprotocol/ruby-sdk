# frozen_string_literal: true

module Arcp
  module Session
    Bye = Data.define(:reason) do
      def self.from_h(h) = new(reason: h.transform_keys(&:to_s)['reason'])
      def to_h = { 'reason' => reason }.compact
    end
  end
end
