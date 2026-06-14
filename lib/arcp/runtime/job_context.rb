# frozen_string_literal: true

require 'async/queue'
require 'base64'
require 'bigdecimal'
require 'time'

module Arcp
  module Runtime
    # Passed to an agent handler. Exposes emission seams (events,
    # progress, tool calls, streamed result) and read-only state
    # (job_id, agent, input, lease).
    class JobContext
      attr_reader :job_id, :agent, :input, :lease, :event_seq

      def done? = @done

      def initialize(job_id:, agent:, input:, lease:, sink:, clock: Arcp::SystemClock.new)
        @job_id = job_id
        @agent = agent
        @input = input
        @lease = lease
        @sink = sink
        @clock = clock
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
        # Spec §9.6: a cost.* metric whose unit matches a budgeted currency
        # decrements that counter. cost.budget.* names are budget telemetry,
        # not charges, and are not applied.
        record_cost_metric(name, value, unit)
        emit(kind: Arcp::Job::EventKind::METRIC,
             body: Arcp::Job::EventBody::Metric.new(name: name, value: value, unit: unit))
      end

      # Spec §9.3/§9.6: synchronous authority check that the runtime mediates
      # before an authority-bearing operation. Raises BUDGET_EXHAUSTED if any
      # budget counter is depleted, then PERMISSION_DENIED if the capability is
      # not covered by the effective lease. Jobs without a lease are
      # unrestricted. Returns the capability so callers can guard inline.
      def authorize!(capability)
        lm = lease_manager
        return capability unless lm

        lm.budget_exhausted!(@job_id)
        lm.check!(@job_id, capability: capability)
        capability
      end

      # Spec §9.7: reject invocation of a model outside the lease's model.use
      # with PERMISSION_DENIED (after the budget check). Returns the model id.
      def use_model!(model_id)
        lm = lease_manager
        return model_id unless lm

        lm.budget_exhausted!(@job_id)
        lm.check_model!(@job_id, model_id: model_id)
        model_id
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
        # Spec §14: the credential `value` MUST NOT be echoed to subscribers.
        # The rotation status event fans out to every attached subscriber, so
        # it carries only the credential id; the new value is already known to
        # the agent that rotated it and is never broadcast.
        status(
          phase: 'credential_rotated',
          fields: { 'id' => new_id || id }
        )
      end

      # Spec §9.3: a tool invocation is an authority-bearing operation, so the
      # lease/budget is checked before the tool_call event is emitted. The
      # capability defaults to `tool.call`; pass a more specific capability
      # (e.g. `fs.write`, `net.fetch`) when the lease grants those.
      def tool_call(call_id:, tool:, args:, capability: 'tool.call')
        authorize!(capability)
        emit(kind: Arcp::Job::EventKind::TOOL_CALL,
             body: Arcp::Job::EventBody::ToolCall.new(call_id: call_id, tool: tool, args: args))
      end

      def tool_result(call_id:, result: nil, error: nil)
        emit(kind: Arcp::Job::EventKind::TOOL_RESULT,
             body: Arcp::Job::EventBody::ToolResult.new(call_id: call_id, result: result, error: error))
      end

      def stream_result(encoding: 'utf8', max_chunk_bytes: ChunkWriter::DEFAULT_MAX_CHUNK_BYTES,
                        max_total_bytes: ChunkWriter::DEFAULT_MAX_TOTAL_BYTES, &block)
        raise Arcp::Errors::ProtocolViolation, 'result already finalized' if @done

        @chunked = true
        @result_id = Arcp::Ids.result_id

        writer = ChunkWriter.new(
          ctx: self, encoding: encoding, result_id: @result_id,
          max_chunk_bytes: max_chunk_bytes, max_total_bytes: max_total_bytes
        )
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
            completed_at: @clock.now.iso8601
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

      private

      def lease_manager = @sink.runtime&.lease_manager

      def record_cost_metric(name, value, unit)
        return unless unit && name.is_a?(String)
        return unless name.start_with?('cost.')
        return if name.start_with?('cost.budget')

        lm = lease_manager
        return unless lm

        counter = lm.counter(@job_id)
        return if counter.nil? || !counter.remaining.key?(unit)

        amount = coerce_amount(value)
        return if amount.nil?

        lm.record_cost(@job_id, unit, amount)
      end

      def coerce_amount(value)
        case value
        when BigDecimal then value
        when Integer then BigDecimal(value)
        else BigDecimal(value.to_s)
        end
      rescue ArgumentError, TypeError
        nil
      end

      # @api private
      class ChunkWriter
        # Spec §14: runtimes SHOULD cap individual chunk size (e.g. 1 MB) and
        # total streamed result size; exceeding either MUST yield
        # INTERNAL_ERROR. Defaults are conservative and overridable per stream.
        DEFAULT_MAX_CHUNK_BYTES = 1_048_576          # 1 MiB
        DEFAULT_MAX_TOTAL_BYTES = 256 * 1_048_576    # 256 MiB

        def initialize(ctx:, encoding:, result_id:,
                       max_chunk_bytes: DEFAULT_MAX_CHUNK_BYTES,
                       max_total_bytes: DEFAULT_MAX_TOTAL_BYTES)
          @ctx = ctx
          @encoding = encoding
          @result_id = result_id
          @max_chunk_bytes = max_chunk_bytes
          @max_total_bytes = max_total_bytes
          @seq = 0
          @bytes = 0
          @closed = false
        end

        def write(chunk, more: true)
          raise Arcp::Errors::ProtocolViolation, 'stream closed' if @closed

          enforce_size_caps!(chunk.bytesize)
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

        private

        def enforce_size_caps!(incoming_bytes)
          if @max_chunk_bytes && incoming_bytes > @max_chunk_bytes
            raise Arcp::Errors::Internal.new(
              "result_chunk exceeds per-chunk cap: #{incoming_bytes} > #{@max_chunk_bytes}",
              details: { 'result_id' => @result_id, 'limit' => @max_chunk_bytes }
            )
          end

          return unless @max_total_bytes && (@bytes + incoming_bytes) > @max_total_bytes

          raise Arcp::Errors::Internal.new(
            "streamed result exceeds total cap: #{@bytes + incoming_bytes} > #{@max_total_bytes}",
            details: { 'result_id' => @result_id, 'limit' => @max_total_bytes }
          )
        end
      end
    end
  end
end
