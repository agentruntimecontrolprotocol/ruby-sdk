# frozen_string_literal: true

require 'async'
require 'async/http/endpoint'
require 'async/http/server'
require 'async/websocket/adapters/http'
require 'async/websocket/client'

require 'arcp/envelope'
require 'arcp/error'
require 'arcp/json'
require 'arcp/transport/transport'

module Arcp
  module Transport
    # WebSocket transport (§22 mandatory).
    #
    # Server side: `Arcp::Transport::Websocket::Server` listens on
    # an `Async::HTTP::Endpoint` and yields a connected
    # `WebsocketTransport` to a handler block per connection.
    #
    # Client side: `Arcp::Transport::Websocket.connect(url)` returns
    # a connected `WebsocketTransport`.
    module Websocket
      # Server-side helper.
      class Server
        # @param endpoint [Async::HTTP::Endpoint]
        # @param logger [Logger]
        def initialize(endpoint:, logger: Logger.new(IO::NULL))
          @endpoint = endpoint
          @logger = logger
        end

        # Run the server. Yields a `WebsocketTransport` per accepted
        # connection. Blocks until the server task is stopped.
        #
        # @yieldparam transport [WebsocketTransport]
        def run(&)
          handler = build_handler(&)
          server = Async::HTTP::Server.new(handler, @endpoint)
          @tasks = Array(server.run)
          @tasks.each(&:wait)
        end

        # Stop the server.
        def stop
          @tasks&.each(&:stop)
        end

        private

        def build_handler(&)
          lambda do |request|
            Async::WebSocket::Adapters::HTTP.open(request) do |connection|
              transport = WebsocketTransport.new(connection: connection)
              yield(transport)
            ensure
              transport&.close
            end || ::Protocol::HTTP::Response[404, {}, ['websocket only']]
          end
        end
      end

      # Connect a client to a remote runtime over WebSocket.
      #
      # @param url [String] e.g. "ws://localhost:7777/"
      # @return [WebsocketTransport]
      def self.connect(url)
        endpoint = Async::HTTP::Endpoint.parse(url)
        connection = Async::WebSocket::Client.connect(endpoint)
        WebsocketTransport.new(connection: connection)
      end
    end

    # Transport adapter wrapping an Async::WebSocket connection.
    class WebsocketTransport
      include Contract

      def initialize(connection:)
        @connection = connection
        @closed = false
        @write_mutex = Mutex.new
      end

      def send_envelope(envelope)
        raise Arcp::Error::Unavailable, 'websocket closed' if @closed

        json = Arcp::Json.encode_envelope(envelope)
        @write_mutex.synchronize { @connection.write(json) }
        @connection.flush
      end

      def receive_envelope
        return nil if @closed

        message = @connection.read
        return nil if message.nil?

        text = message.respond_to?(:buffer) ? message.buffer : message.to_s
        Arcp::Json.decode_envelope(text)
      rescue ::Protocol::WebSocket::ClosedError, EOFError
        @closed = true
        nil
      end

      def closed?
        @closed
      end

      def close
        return if @closed

        @closed = true
        begin
          @connection.close
        rescue StandardError
          # already closed
        end
      end
    end
  end
end
