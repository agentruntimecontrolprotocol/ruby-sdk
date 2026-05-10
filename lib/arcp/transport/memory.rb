# frozen_string_literal: true

require 'async'
require 'async/queue'

require 'arcp/transport/transport'

module Arcp
  module Transport
    # In-process transport for tests and samples. A linked pair of
    # `Memory` transports — one for each side of the connection.
    #
    # Use `Arcp::Transport::Memory.pair` to construct a (client, runtime)
    # tuple where envelopes sent on one are received on the other.
    class Memory
      include Contract

      class << self
        # @return [Array(Memory, Memory)] (client_side, runtime_side)
        def pair
          to_runtime = Async::Queue.new
          to_client  = Async::Queue.new
          client_side  = new(outbound: to_runtime, inbound: to_client, label: 'client')
          runtime_side = new(outbound: to_client,  inbound: to_runtime, label: 'runtime')
          [client_side, runtime_side]
        end
      end

      attr_reader :label

      def initialize(outbound:, inbound:, label: 'memory')
        @outbound = outbound
        @inbound = inbound
        @label = label
        @closed = false
      end

      def send_envelope(envelope)
        raise Arcp::Error::Unavailable, "transport #{label} is closed" if @closed

        @outbound.enqueue(envelope)
      end

      def receive_envelope
        return nil if @closed

        msg = @inbound.dequeue
        msg.equal?(:__arcp_close__) ? nil : msg
      end

      def closed?
        @closed
      end

      def close
        return if @closed

        @closed = true
        @outbound.enqueue(:__arcp_close__)
      end
    end
  end
end
