# frozen_string_literal: true

module Arcp
  module Session
    Ping = Data.define(:nonce, :sent_at) do
      def self.from_h(h)
        h = h.transform_keys(&:to_s)
        new(nonce: h.fetch('nonce'), sent_at: h.fetch('sent_at'))
      end

      def to_h = { 'nonce' => nonce, 'sent_at' => sent_at }
    end
  end
end
