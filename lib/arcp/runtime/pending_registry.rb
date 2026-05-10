# frozen_string_literal: true

require 'async'
require 'async/notification'

module Arcp
  module Runtime
    # Pending request registry — maps `correlation_id` to a one-shot
    # `Async::Notification` that delivers the value when it arrives.
    #
    # Used to await `human.input.response`, `permission.grant`, and any
    # other request/response pattern that crosses fiber boundaries.
    class PendingRegistry
      def initialize
        @waiters = {}
        @resolved = {}
        @mutex = Mutex.new
      end

      # Wait for a response with the given correlation id.
      #
      # @param correlation_id [String]
      # @param timeout_seconds [Numeric, nil]
      # @return [Object]
      # @raise [Arcp::Error::DeadlineExceeded]
      def await(correlation_id, timeout_seconds: nil)
        notification = Async::Notification.new
        @mutex.synchronize do
          if @resolved.key?(correlation_id)
            value = @resolved.delete(correlation_id)
            return value
          end
          @waiters[correlation_id] = notification
        end

        if timeout_seconds
          Async::Task.current.with_timeout(timeout_seconds) { notification.wait }
        else
          notification.wait
        end
      rescue Async::TimeoutError
        raise Arcp::Error::DeadlineExceeded,
              "timed out waiting for #{correlation_id} after #{timeout_seconds}s"
      ensure
        @mutex.synchronize { @waiters.delete(correlation_id) }
      end

      # Resolve a pending wait with a value, or buffer it if no waiter is
      # registered yet.
      #
      # @param correlation_id [String]
      # @param value [Object]
      # @return [Boolean] whether a waiter received the value immediately
      def resolve(correlation_id, value)
        @mutex.synchronize do
          notification = @waiters.delete(correlation_id)
          if notification
            notification.signal(value)
            true
          else
            @resolved[correlation_id] = value
            false
          end
        end
      end

      # @return [Integer]
      def pending_count
        @mutex.synchronize { @waiters.size }
      end
    end
  end
end
