# frozen_string_literal: true

module Arcp
  module Runtime
    # In-memory ring of buffered events keyed by session_id. The runtime
    # uses this for the resume window and `session.ack`-driven early
    # eviction. A SQLite-backed variant (same API) is suitable for
    # multi-process runtimes; for v1 we ship the in-memory implementation
    # used by tests and the Falcon-hosted single-process runtime.
    class EventLog
      def initialize(window_sec: 300, clock: Arcp::SystemClock.new)
        @window_sec = window_sec
        @clock = clock
        @sessions = Hash.new { |h, k| h[k] = [] }
        @floor = Hash.new(0)
        @mutex = Mutex.new
      end

      def append(session_id, envelope)
        @mutex.synchronize do
          @sessions[session_id] << [envelope, @clock.monotonic]
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

      def replay(session_id, from_event_seq: nil)
        @mutex.synchronize do
          @sessions[session_id].each_with_object([]) do |(env, _t), out|
            next if env.event_seq.nil?
            next if from_event_seq && env.event_seq < from_event_seq

            out << env
          end
        end
      end

      # Evict events past the resume window (advisory; consumer drives via timer).
      def expire!
        now = @clock.monotonic
        @mutex.synchronize do
          @sessions.each_value do |buf|
            buf.reject! { |(_e, t)| (now - t) > @window_sec }
          end
        end
      end

      # @api private
      def buffer_size(session_id) = @sessions[session_id].size
    end
  end
end
