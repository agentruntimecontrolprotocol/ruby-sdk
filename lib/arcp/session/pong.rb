# frozen_string_literal: true

module Arcp
  module Session
    Pong = Data.define(:ping_nonce, :received_at) do
      def self.from_h(h)
        h = h.transform_keys(&:to_s)
        new(ping_nonce: h.fetch('ping_nonce'), received_at: h.fetch('received_at'))
      end

      def to_h = { 'ping_nonce' => ping_nonce, 'received_at' => received_at }
    end
  end
end
