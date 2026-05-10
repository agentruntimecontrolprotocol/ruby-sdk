# frozen_string_literal: true

require 'arcp/envelope'
require 'arcp/error'
require 'arcp/json'
require 'arcp/transport/transport'

module Arcp
  module Transport
    # Newline-delimited JSON envelopes over a pair of IO objects (by
    # default `$stdin` for read and `$stdout` for write).
    #
    # Each envelope is encoded as a single JSON line with no embedded
    # newlines (JSON.generate guarantees this).
    class Stdio
      include Contract

      def initialize(input: $stdin, output: $stdout)
        @input = input
        @output = output
        @write_mutex = Mutex.new
        @closed = false
      end

      def send_envelope(envelope)
        raise Arcp::Error::Unavailable, 'stdio transport closed' if @closed

        line = Arcp::Json.encode_envelope(envelope)
        @write_mutex.synchronize do
          @output.write(line)
          @output.write("\n")
          @output.flush
        end
      end

      def receive_envelope
        return nil if @closed

        line = @input.gets
        return nil if line.nil?

        Arcp::Json.decode_envelope(line.chomp)
      end

      def closed?
        @closed
      end

      def close
        @closed = true
        begin
          @output.flush
        rescue StandardError
          nil
        end
      end
    end
  end
end
