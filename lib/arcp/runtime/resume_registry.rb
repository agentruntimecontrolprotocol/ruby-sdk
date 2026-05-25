# frozen_string_literal: true

module Arcp
  module Runtime
    # In-memory mapping of resume tokens to the sessions that may be
    # reattached. Entries are kept for `window_sec` past the session's
    # last activity so a client that briefly disconnects can hello with
    # `resume: { 'token' => ..., 'last_event_seq' => ... }` and restore
    # the prior session id, principal, and event cursor.
    class ResumeRegistry
      Entry = Struct.new(:session_id, :principal_id, :token, :registered_monotonic,
                         :disconnected_monotonic, :window_sec, :last_processed_seq)

      def initialize(window_sec: 300, clock: Arcp::SystemClock.new)
        @window_sec = window_sec
        @clock = clock
        @by_token = {}
        @mutex = Mutex.new
      end

      # Registers a fresh resume token. Returns the recorded entry.
      def register(token:, session_id:, principal_id:, last_processed_seq: 0)
        entry = Entry.new(session_id, principal_id, token, @clock.monotonic, nil, @window_sec,
                          last_processed_seq)
        @mutex.synchronize { @by_token[token] = entry }
        entry
      end

      # Marks the session disconnected so the resume window starts counting.
      def mark_disconnected(token, last_processed_seq: nil)
        @mutex.synchronize do
          entry = @by_token[token]
          next unless entry

          entry.disconnected_monotonic = @clock.monotonic
          entry.last_processed_seq = last_processed_seq if last_processed_seq
        end
      end

      # Marks the session reconnected; clears the disconnect timer.
      def mark_reconnected(token)
        @mutex.synchronize do
          entry = @by_token[token]
          entry&.disconnected_monotonic = nil
        end
      end

      def forget(token)
        @mutex.synchronize { @by_token.delete(token) }
      end

      # Looks up a token, evicting expired entries. Returns the entry or nil.
      def lookup(token)
        @mutex.synchronize do
          entry = @by_token[token]
          return nil unless entry

          if expired?(entry)
            @by_token.delete(token)
            return nil
          end
          entry
        end
      end

      # Drops entries whose disconnect window has elapsed.
      def expire!
        @mutex.synchronize do
          @by_token.reject! { |_, entry| expired?(entry) }
        end
      end

      # @api private
      def size = @mutex.synchronize { @by_token.size }

      private

      def expired?(entry)
        return false if entry.disconnected_monotonic.nil?

        (@clock.monotonic - entry.disconnected_monotonic) > entry.window_sec
      end
    end
  end
end
