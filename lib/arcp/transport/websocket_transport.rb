# frozen_string_literal: true

require_relative '../serializer'

module Arcp
  module Transport
    # WebSocket transport built on `async-websocket`. The `connection`
    # argument is an open `Async::WebSocket::Connection`.
    class WebSocketTransport < Base
      def initialize(connection:)
        super()
        @connection = connection
        @closed = false
      end

      def send(envelope)
        raise IOError, 'transport closed' if @closed

        @connection.write(envelope.to_json)
        @connection.flush if @connection.respond_to?(:flush)
        nil
      end

      def receive
        message = @connection.read
        return nil if message.nil?

        bytes = message.respond_to?(:buffer) ? message.buffer : message.to_s
        Arcp::Envelope.from_json(bytes)
      rescue EOFError, IOError
        @closed = true
        nil
      end

      def close(reason: nil)
        return if @closed

        @closed = true
        @connection.close if @connection.respond_to?(:close)
      rescue StandardError
        nil
      end

      def closed? = @closed
    end
  end
end
