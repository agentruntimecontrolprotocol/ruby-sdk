# frozen_string_literal: true

module Arcp
  module Session
    Ack = Data.define(:last_processed_seq) do
      def self.from_h(h)
        h = h.transform_keys(&:to_s)
        new(last_processed_seq: h.fetch('last_processed_seq'))
      end

      def to_h = { 'last_processed_seq' => last_processed_seq }
    end
  end
end
