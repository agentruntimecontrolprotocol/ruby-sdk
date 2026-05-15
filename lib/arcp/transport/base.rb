# frozen_string_literal: true

require_relative '../envelope'

module Arcp
  module Transport
    # Abstract transport interface. Implementations carry frames, not
    # message types — decoding is `Arcp::Envelope.from_h`.
    #
    # `#send` accepts an `Arcp::Envelope` and serializes it.
    # `#receive` suspends the calling fiber until an envelope arrives,
    # then returns it (or nil on clean close).
    class Base
      def send(envelope)
        raise NotImplementedError
      end

      def receive
        raise NotImplementedError
      end

      def close(reason: nil)
        raise NotImplementedError
      end

      def closed? = false
    end
  end
end
