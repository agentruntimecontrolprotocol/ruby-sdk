# frozen_string_literal: true

require_relative '../serializer'

module Arcp
  module Transport
    # Newline-delimited JSON over a pair of IOs. The child process reads
    # from stdin and writes to stdout; the parent connects with its
    # pipe ends. Exit on EOF.
    class StdioTransport < Base
      def initialize(input: $stdin, output: $stdout)
        super()
        @input = input
        @output = output
        @closed = false
        @write_mutex = Mutex.new
      end

      def send(envelope)
        raise IOError, 'transport closed' if @closed

        line = Arcp::Serializer.dump(envelope.to_h)
        @write_mutex.synchronize do
          @output.write(line)
          @output.write("\n")
          @output.flush
        end
        nil
      end

      def receive
        return nil if @closed

        line = @input.gets
        if line.nil?
          @closed = true
          return nil
        end

        Arcp::Envelope.from_json(line)
      end

      def close(reason: nil)
        return if @closed

        @closed = true
        @output.close unless @output.closed? || @output == $stdout
        @input.close unless @input.closed? || @input == $stdin
      rescue IOError
        nil
      end

      def closed? = @closed
    end
  end
end
