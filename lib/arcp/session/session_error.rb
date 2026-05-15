# frozen_string_literal: true

module Arcp
  module Session
    SessionError = Data.define(:code, :message, :retryable, :details) do
      def self.from_h(h)
        h = h.transform_keys(&:to_s)
        new(
          code: h.fetch('code'),
          message: h['message'],
          retryable: h.fetch('retryable', false),
          details: h['details'] || {}
        )
      end

      def to_h
        h = { 'code' => code, 'message' => message, 'retryable' => retryable }
        h['details'] = details unless details.nil? || details.empty?
        h
      end
    end
  end
end
