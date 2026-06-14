# frozen_string_literal: true

module Arcp
  module Runtime
    # In-memory ring of buffered events keyed by session_id, with a
    # secondary index by job_id so that `job.subscribe` history replays
    # can resolve from the originating job's stream regardless of which
    # session emitted the envelopes. The runtime uses this for the
    # replay window and `session.ack`-driven early eviction. The shipped
    # implementation is in-memory; persistence can be layered on later
    # without changing the public API.
    class EventLog
      def initialize(window_sec: 300, clock: Arcp::SystemClock.new)
        @window_sec = window_sec
        @clock = clock
        @sessions = Hash.new { |h, k| h[k] = [] }
        @jobs = Hash.new { |h, k| h[k] = [] }
        @floor = Hash.new(0)
        @mutex = Mutex.new
      end

      def append(session_id, envelope)
        now = @clock.monotonic
        entry = [envelope, now]
        @mutex.synchronize do
          # Self-evict on write so per-session/per-job buffers can never grow
          # unbounded purely from elapsed time, independent of session.ack.
          evict_expired!(now)
          @sessions[session_id] << entry
          @jobs[envelope.job_id] << entry if envelope.job_id
        end
        envelope
      end

      def floor(session_id) = @floor[session_id]

      def evict_up_to(session_id, seq)
        @mutex.synchronize do
          @floor[session_id] = [@floor[session_id], seq].max
          @sessions[session_id].reject! do |env, _t|
            env.event_seq && env.event_seq <= seq
          end
        end
      end

      # Replays buffered envelopes for a session in arrival order. Used
      # for resume token replay where the session id frames the cursor.
      # Terminal envelopes (`job.result`, `job.error`) carry no
      # `event_seq` and are always included so a resuming client can
      # observe the final job state alongside any missed events.
      def replay(session_id, from_event_seq: nil)
        @mutex.synchronize do
          @sessions[session_id].each_with_object([]) do |(env, _t), out|
            next if env.event_seq && from_event_seq && env.event_seq < from_event_seq

            out << env
          end
        end
      end

      # Replays buffered envelopes for a job's stream regardless of which
      # session originally produced them. Used by `job.subscribe`
      # history replay so observers see the full job timeline, including
      # the terminal `job.result` / `job.error` envelope.
      def replay_job(job_id, from_event_seq: nil)
        @mutex.synchronize do
          @jobs[job_id].each_with_object([]) do |(env, _t), out|
            next if env.event_seq && from_event_seq && env.event_seq < from_event_seq

            out << env
          end
        end
      end

      # Evict events past the resume window. Driven automatically on every
      # {#append}; also exposed so a runtime MAY schedule it on a periodic
      # timer to reclaim idle buffers between writes.
      def expire!
        @mutex.synchronize { evict_expired!(@clock.monotonic) }
      end

      private

      # Drops entries older than the resume window. Caller holds @mutex.
      def evict_expired!(now)
        @sessions.each_value do |buf|
          buf.reject! { |(_e, t)| (now - t) > @window_sec }
        end
        @jobs.each_value do |buf|
          buf.reject! { |(_e, t)| (now - t) > @window_sec }
        end
      end

      public

      # @api private
      def buffer_size(session_id) = @sessions[session_id].size
      # @api private
      def job_buffer_size(job_id) = @jobs[job_id].size
    end
  end
end
