# frozen_string_literal: true

require 'async/queue'
require 'base64'
require 'time'

module Arcp
  module Runtime
    # Passed to an agent handler. Exposes emission seams (events,
    # progress, tool calls, streamed result) and read-only state
    # (job_id, agent, input, lease).
    class JobContext
      attr_reader :job_id, :agent, :input, :lease, :event_seq

      def done? = @done

      def initialize(job_id:, agent:, input:, lease:, sink:)
        @job_id = job_id
        @agent = agent
        @input = input
        @lease = lease
        @sink = sink
        @event_seq = 0
        @result_id = nil
        @result_totals = nil
        @writer = nil
        @done = false
        @chunked = false
        @mutex = Mutex.new
      end

      def emit(kind:, body:)
        event = Arcp::Job::Event.new(kind: kind, body: body)
        @event_seq = @sink.publish_event(@job_id, event)
        event
      end

      def log(level:, message:, **fields)
        emit(kind: Arcp::Job::EventKind::LOG,
             body: Arcp::Job::EventBody::Log.new(level: level, message: message, fields: fields))
      end

      def progress(current:, total: nil, units: nil, message: nil)
        emit(kind: Arcp::Job::EventKind::PROGRESS,
             body: Arcp::Job::EventBody::Progress.new(current: current, total: total, units: units,
                                                      message: message))
      end

      def metric(name:, value:, unit: nil)
        emit(kind: Arcp::Job::EventKind::METRIC,
             body: Arcp::Job::EventBody::Metric.new(name: name, value: value, unit: unit))
      end

      def status(phase:, message: nil, fields: {})
        emit(kind: Arcp::Job::EventKind::STATUS,
             body: Arcp::Job::EventBody::Status.new(phase: phase, message: message,
                                                    fields: fields))
      end

      def rotate_credential(id:, new_value:)
        new_id = @sink.runtime.credential_registry&.rotate(
          job_id: job_id,
          credential_id: id,
          new_value: new_value
        )
        status(
          phase: 'credential_rotated',
          fields: { 'id' => new_id || id, 'value' => new_value }
        )
      end

      def tool_call(call_id:, tool:, args:)
        emit(kind: Arcp::Job::EventKind::TOOL_CALL,
             body: Arcp::Job::EventBody::ToolCall.new(call_id: call_id, tool: tool, args: args))
      end

      def tool_result(call_id:, result: nil, error: nil)
        emit(kind: Arcp::Job::EventKind::TOOL_RESULT,
             body: Arcp::Job::EventBody::ToolResult.new(call_id: call_id, result: result, error: error))
      end

      def stream_result(encoding: 'utf8', &block)
        raise Arcp::Errors::ProtocolViolation, 'result already finalized' if @done

        @chunked = true
        @result_id = Arcp::Ids.result_id

        writer = ChunkWriter.new(ctx: self, encoding: encoding, result_id: @result_id)
        @writer = writer
        if block
          yield writer
          writer.close
          writer.totals
        else
          writer
        end
      end

      # @api private
      # Called by ChunkWriter#close so non-block callers don't have to push
      # totals back into the context manually before {#finish}.
      def record_chunk_totals(totals)
        @result_totals = totals
      end

      def finish(result: nil)
        raise Arcp::Errors::ProtocolViolation, 'result already finalized' if @done

        if @chunked && !result.nil?
          raise Arcp::Errors::ProtocolViolation, 'cannot mix inline result with result_chunk stream'
        end

        @writer&.close if @chunked
        totals = @result_totals || @writer&.totals
        @done = true

        @sink.publish_result(
          @job_id,
          Arcp::Job::Result.new(
            job_id: @job_id, final_status: 'success',
            result: result,
            result_id: @chunked ? @result_id : nil,
            result_size: @chunked ? totals && totals[:bytes] : nil,
            completed_at: Time.now.utc.iso8601
          )
        )
      end

      # Spec §7.3: terminal states are success|error|cancelled|timed_out.
      # The timeout path passes `final_status: 'timed_out'`; all other
      # failures terminate as 'error'.
      def fail!(code:, message: nil, retryable: false, details: {}, final_status: 'error')
        raise Arcp::Errors::ProtocolViolation, 'result already finalized' if @done

        @done = true
        @sink.publish_error(
          @job_id,
          Arcp::Job::JobError.new(
            job_id: @job_id, final_status: final_status,
            code: code, message: message, retryable: retryable, details: details
          )
        )
      end

      # @api private
      class ChunkWriter
        def initialize(ctx:, encoding:, result_id:)
          @ctx = ctx
          @encoding = encoding
          @result_id = result_id
          @seq = 0
          @bytes = 0
          @closed = false
        end

        def write(chunk, more: true)
          raise Arcp::Errors::ProtocolViolation, 'stream closed' if @closed

          data = case @encoding
                 when 'base64' then Base64.strict_encode64(chunk)
                 else chunk.dup.force_encoding('UTF-8')
                 end
          @bytes += chunk.bytesize
          body = Arcp::Job::EventBody::ResultChunk.new(
            result_id: @result_id, chunk_seq: @seq, data: data,
            encoding: @encoding, more: more
          )
          @ctx.emit(kind: Arcp::Job::EventKind::RESULT_CHUNK, body: body)
          @seq += 1
        end

        def close
          return if @closed

          @closed = true
          @ctx.record_chunk_totals(totals)
        end

        def totals = { bytes: @bytes, chunks: @seq, result_id: @result_id }
      end
    end
  end
end
