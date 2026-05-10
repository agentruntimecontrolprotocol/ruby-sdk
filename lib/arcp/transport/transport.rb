# frozen_string_literal: true

module Arcp
  module Transport
    # Abstract transport contract.
    #
    # Implementations must provide `send` (write an envelope) and
    # `receive` (read the next envelope, blocking if none available).
    # `closed?` returns whether the underlying channel has been
    # closed by either side.
    #
    # Transports operate on `Arcp::Envelope` objects, not raw JSON.
    module Contract
      # Send an envelope across the transport.
      #
      # @param envelope [Arcp::Envelope]
      # @return [void]
      def send_envelope(envelope)
        raise NotImplementedError
      end

      # Receive the next envelope. Blocks (in fiber-friendly fashion)
      # until one is available. Returns nil on close.
      #
      # @return [Arcp::Envelope, nil]
      def receive_envelope
        raise NotImplementedError
      end

      # @return [Boolean]
      def closed?
        raise NotImplementedError
      end

      # @return [void]
      def close
        raise NotImplementedError
      end
    end
  end
end
