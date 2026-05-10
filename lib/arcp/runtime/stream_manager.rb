# frozen_string_literal: true

require 'async/queue'

require 'arcp/error'
require 'arcp/error_code'
require 'arcp/ids'
require 'arcp/messages/streaming'

module Arcp
  module Runtime
    # Per-stream record.
    class StreamRecord
      attr_reader :stream_id, :session_id, :kind, :sequence

      def initialize(stream_id:, session_id:, kind:)
        @stream_id = stream_id
        @session_id = session_id
        @kind = kind
        @sequence = 0
        @closed = false
      end

      def next_sequence!
        @sequence += 1
      end

      def close!
        @closed = true
      end

      def closed?
        @closed
      end
    end

    # Manages stream lifecycle and per-stream sequence numbers.
    #
    # Backpressure is implemented by `Async::LimitedQueue` per stream:
    # once full, `chunk` blocks the producer fiber until the consumer
    # drains.
    class StreamManager
      DEFAULT_BACKPRESSURE_LIMIT = 64

      def initialize(emit:, default_limit: DEFAULT_BACKPRESSURE_LIMIT)
        @emit = emit
        @default_limit = default_limit
        @records = {}
        @mutex = Mutex.new
      end

      # Open a stream and return its id. Emits `stream.open`.
      #
      # @param session_id [Arcp::SessionId]
      # @param kind [String] one of Arcp::Messages::Streaming::KNOWN_KINDS
      # @param content_type [String, nil]
      # @param encoding [String, nil]
      # @return [Arcp::StreamId]
      def open(session_id:, kind:, content_type: nil, encoding: nil)
        raise Arcp::Error::InvalidArgument, "unknown stream kind: #{kind}" unless valid_kind?(kind)

        stream_id = StreamId.random
        record = StreamRecord.new(stream_id: stream_id, session_id: session_id, kind: kind)
        @mutex.synchronize { @records[stream_id.value] = record }
        @emit.call(record, Messages::Streaming::StreamOpen.new(
                             kind: kind, content_type: content_type, encoding: encoding, sidecar: false
                           ))
        stream_id
      end

      # Emit a chunk on the given stream.
      def chunk(stream_id, content: nil, data: nil, role: nil, redacted: false, content_type: nil,
                sha256: nil)
        record = lookup!(stream_id)
        raise Arcp::Error::FailedPrecondition, 'stream is closed' if record.closed?

        @emit.call(record, Messages::Streaming::StreamChunk.new(
                             sequence: record.next_sequence!,
                             content: content, data: data, content_type: content_type,
                             sha256: sha256, role: role, redacted: redacted
                           ))
      end

      # Close a stream cleanly.
      def close(stream_id, reason: nil)
        record = lookup!(stream_id)
        return if record.closed?

        record.close!
        @emit.call(record, Messages::Streaming::StreamClose.new(reason: reason))
      end

      # Terminate a stream with an error code (used for cancellation, §10.4).
      def error(stream_id, code:, message:, retryable: false, details: nil)
        record = lookup!(stream_id)
        return if record.closed?

        record.close!
        @emit.call(record, Messages::Streaming::StreamError.new(
                             code: code, message: message, retryable: retryable, details: details
                           ))
      end

      # @api private
      def lookup(stream_id)
        key = stream_id.respond_to?(:value) ? stream_id.value : stream_id
        @mutex.synchronize { @records[key] }
      end

      # @api private
      def lookup!(stream_id)
        record = lookup(stream_id)
        raise Arcp::Error::NotFound, "stream not found: #{stream_id}" if record.nil?

        record
      end

      private

      def valid_kind?(kind)
        Messages::Streaming::KNOWN_KINDS.include?(kind)
      end
    end
  end
end
