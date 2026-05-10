# frozen_string_literal: true

require 'async/queue'

require 'arcp/error'
require 'arcp/error_code'
require 'arcp/ids'
require 'arcp/messages/subscriptions'
require 'arcp/messages/telemetry'
require 'arcp/priority'

module Arcp
  module Runtime
    # Per-subscription record.
    class SubscriptionRecord
      attr_reader :subscription_id, :session_id, :filter, :since
      attr_accessor :live_queue, :closed

      def initialize(subscription_id:, session_id:, filter:, since: nil)
        @subscription_id = subscription_id
        @session_id = session_id
        @filter = filter
        @since = since
        @live_queue = nil
        @closed = false
      end
    end

    # Manages subscriptions: backfill, live tail, and termination (§13).
    class SubscriptionManager
      def initialize(emit:, event_log:, clock: Time)
        @emit = emit
        @event_log = event_log
        @clock = clock
        @records = {}
        @mutex = Mutex.new
      end

      # Compile and register a subscription. Validates the filter against
      # the session's authorization (which for v0.1 is just "same session").
      #
      # @param session_id [Arcp::SessionId]
      # @param filter [Hash]
      # @param since [Hash, nil]
      # @return [Arcp::Runtime::SubscriptionRecord]
      def subscribe(session_id:, filter:, since: nil)
        normalized = normalize_filter(filter)
        authorize!(session_id: session_id, filter: normalized)
        record = SubscriptionRecord.new(
          subscription_id: SubscriptionId.random,
          session_id: session_id,
          filter: normalized,
          since: since
        )
        @mutex.synchronize { @records[record.subscription_id.value] = record }
        record
      end

      # Replay events matching the filter from the event log up to the
      # current snapshot, emit a synthetic backfill_complete marker, and
      # then keep the subscription open for live tail.
      def deliver_backfill(record)
        events = @event_log.replay(
          after_seq: extract_after_seq(record.since),
          session_id: record.filter[:session_id]&.first,
          job_id: record.filter[:job_id]&.first,
          stream_id: record.filter[:stream_id]&.first,
          trace_id: record.filter[:trace_id]&.first,
          types: record.filter[:types]
        )
        events.each do |event|
          next unless filter_matches?(record.filter, event)

          @emit.call(record, Messages::Subscriptions::SubscribeEvent.new(
                               event: event.to_wire_hash, sequence: nil
                             ))
        end
        @emit.call(record, Messages::Subscriptions::SubscribeEvent.new(
                             event: backfill_complete_envelope_hash(record),
                             sequence: nil
                           ))
      end

      def fan_out(envelope)
        @mutex.synchronize do
          @records.each_value do |record|
            next if record.closed
            next unless filter_matches?(record.filter, envelope)

            @emit.call(record, Messages::Subscriptions::SubscribeEvent.new(
                                 event: envelope.to_wire_hash, sequence: nil
                               ))
          end
        end
      end

      def unsubscribe(subscription_id, reason: nil)
        record = @mutex.synchronize { @records.delete(id_value(subscription_id)) }
        return false if record.nil?

        record.closed = true
        @emit.call(record, Messages::Subscriptions::SubscribeClosed.new(
                             code: ErrorCode::OK, reason: reason
                           ))
        true
      end

      def close_with_error(subscription_id, code:, reason:)
        record = @mutex.synchronize { @records.delete(id_value(subscription_id)) }
        return false if record.nil?

        record.closed = true
        @emit.call(record, Messages::Subscriptions::SubscribeClosed.new(
                             code: code, reason: reason
                           ))
        true
      end

      def lookup(subscription_id)
        @mutex.synchronize { @records[id_value(subscription_id)] }
      end

      private

      def id_value(subscription_id)
        subscription_id.respond_to?(:value) ? subscription_id.value : subscription_id
      end

      def normalize_filter(raw)
        sym = symbolize(raw || {})
        {
          session_id: Array(sym[:session_id]),
          job_id: Array(sym[:job_id]),
          stream_id: Array(sym[:stream_id]),
          trace_id: Array(sym[:trace_id]),
          types: Array(sym[:types]),
          min_priority: sym[:min_priority] || Priority::LOW
        }
      end

      def authorize!(session_id:, filter:)
        # v0.1: a subscription may only observe its own session.
        allowed = filter[:session_id].empty? || filter[:session_id].include?(session_id.value)
        raise Arcp::Error::PermissionDenied.new(permission: 'subscribe', resource: 'session') unless allowed
      end

      def filter_matches?(filter, envelope)
        return false if filter[:session_id].any? && !filter[:session_id].include?(envelope.session_id&.value)
        return false if filter[:job_id].any? && !filter[:job_id].include?(envelope.job_id&.value)
        return false if filter[:stream_id].any? && !filter[:stream_id].include?(envelope.stream_id&.value)
        return false if filter[:trace_id].any? && !filter[:trace_id].include?(envelope.trace_id&.value)
        return false if filter[:types].any? && !filter[:types].include?(envelope.type)
        return false unless Priority.meets?(envelope.priority, filter[:min_priority])

        true
      end

      def extract_after_seq(since)
        return nil if since.nil?

        sym = symbolize(since)
        msg_id = sym[:after_message_id]
        return nil if msg_id.nil? || msg_id.empty?

        @event_log.seq_for(msg_id)
      end

      def backfill_complete_envelope_hash(record)
        {
          arcp: Arcp::PROTOCOL_VERSION,
          id: MessageId.random.value,
          type: 'event.emit',
          timestamp: @clock.now.utc.iso8601(6),
          subscription_id: record.subscription_id.value,
          payload: { name: 'subscription.backfill_complete', value: nil, attributes: {} }
        }
      end

      def symbolize(hash)
        return {} if hash.nil?
        return hash if hash.empty? || hash.keys.first.is_a?(Symbol)

        hash.transform_keys(&:to_sym)
      end
    end
  end
end
