# frozen_string_literal: true

require 'async/queue'

module Arcp
  module Transport
    # In-process transport backed by a pair of `Async::Queue`s. Used for
    # tests and same-process server/client wiring.
    class MemoryTransport < Base
      attr_reader :sent

      def initialize(incoming:, outgoing:)
        super()
        @incoming = incoming
        @outgoing = outgoing
        @sent = []
        @closed = false
      end

      def self.pair
        a = Async::Queue.new
        b = Async::Queue.new
        [new(incoming: a, outgoing: b), new(incoming: b, outgoing: a)]
      end

      def send(envelope)
        raise IOError, 'transport closed' if @closed

        @sent << envelope
        @outgoing.enqueue(envelope)
        nil
      end

      def receive
        return nil if @closed && @incoming.empty?

        value = @incoming.dequeue
        return nil if value.equal?(:__arcp_close__)

        value
      end

      def close(reason: nil)
        return if @closed

        @closed = true
        @outgoing.enqueue(:__arcp_close__)
        @incoming.enqueue(:__arcp_close__) if @incoming.empty?
      end

      def closed? = @closed
    end
  end
end
