# frozen_string_literal: true

require 'sqlite3'
require 'json'

require 'arcp/error'
require 'arcp/json'

module Arcp
  module Store
    # SQLite-backed event log (§19, §6.4).
    #
    # Stores envelopes by monotonically increasing sequence number with
    # transport-level idempotency on `message_id`. Supports replay by
    # session/job/stream and message-id-based resume.
    #
    # Thread/fiber safety: the underlying SQLite3 connection is wrapped
    # in a Mutex; concurrent writes from multiple fibers are serialized.
    # Reads may interleave because SQLite3 supports concurrent readers
    # against the same connection in serialized mode.
    class EventLog
      SCHEMA_PATH = File.expand_path('schema.sql', __dir__)

      DEFAULT_RETENTION_SECONDS = 7 * 24 * 60 * 60 # 7 days

      attr_reader :path, :retention_seconds

      # @param path [String] file path or `:memory:`
      # @param retention_seconds [Integer]
      # @param clock [#now]
      def initialize(path: ':memory:', retention_seconds: DEFAULT_RETENTION_SECONDS, clock: Time)
        @path = path
        @retention_seconds = retention_seconds
        @clock = clock
        @mutex = Mutex.new
        @db = SQLite3::Database.new(path)
        @db.results_as_hash = true
        @db.execute_batch(File.read(SCHEMA_PATH))
      end

      # Append an envelope. Idempotent on `envelope.id`: a duplicate
      # `message_id` returns the previously assigned `monotonic_seq`
      # without re-inserting.
      #
      # @param envelope [Arcp::Envelope]
      # @return [Integer] monotonic_seq
      def append(envelope)
        json = Arcp::Json.encode_envelope(envelope)
        now_ms = clock_ms
        params = [
          envelope.id.value,
          envelope.type,
          envelope.session_id&.value,
          envelope.job_id&.value,
          envelope.stream_id&.value,
          envelope.subscription_id&.value,
          envelope.trace_id&.value,
          envelope.priority,
          envelope.timestamp.utc.iso8601(6),
          json,
          now_ms
        ]
        @mutex.synchronize do
          @db.execute(INSERT_SQL, params)
          @db.last_insert_row_id
        end
      rescue SQLite3::ConstraintException
        @mutex.synchronize do
          row = @db.get_first_row(
            'SELECT monotonic_seq FROM arcp_events WHERE message_id = ?',
            [envelope.id.value]
          )
          row && row['monotonic_seq']
        end
      end

      INSERT_SQL = <<~SQL
        INSERT INTO arcp_events (
          message_id, type, session_id, job_id, stream_id,
          subscription_id, trace_id, priority, timestamp,
          envelope_json, inserted_at_ms
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      private_constant :INSERT_SQL

      # Look up the monotonic sequence for a message id.
      #
      # @param message_id [Arcp::MessageId, String]
      # @return [Integer, nil]
      def seq_for(message_id)
        value = message_id.respond_to?(:value) ? message_id.value : message_id
        @mutex.synchronize do
          row = @db.get_first_row('SELECT monotonic_seq FROM arcp_events WHERE message_id = ?', [value])
          row && row['monotonic_seq']
        end
      end

      # Replay events matching the given filter.
      #
      # @param after_seq [Integer, nil]  exclusive lower bound on monotonic_seq
      # @param session_id [String, nil]
      # @param job_id [String, nil]
      # @param stream_id [String, nil]
      # @param trace_id [String, nil]
      # @param types [Array<String>, nil]
      # @return [Array<Arcp::Envelope>]
      def replay(after_seq: nil, session_id: nil, job_id: nil, stream_id: nil,
                 trace_id: nil, types: nil)
        clauses, params = build_replay_filter(
          after_seq: after_seq, session_id: session_id, job_id: job_id,
          stream_id: stream_id, trace_id: trace_id, types: types
        )
        sql = +'SELECT envelope_json FROM arcp_events'
        sql << " WHERE #{clauses.join(' AND ')}" unless clauses.empty?
        sql << ' ORDER BY monotonic_seq ASC'
        rows = @mutex.synchronize { @db.execute(sql, params) }
        rows.map { |row| Arcp::Json.decode_envelope(row['envelope_json']) }
      end

      # Number of events in the log.
      #
      # @return [Integer]
      def size
        @mutex.synchronize do
          @db.get_first_value('SELECT COUNT(*) FROM arcp_events')
        end
      end

      # Delete events whose `inserted_at_ms` is older than retention.
      #
      # @return [Integer] rows deleted
      def sweep_expired
        cutoff = clock_ms - (retention_seconds * 1000)
        @mutex.synchronize do
          @db.execute('DELETE FROM arcp_events WHERE inserted_at_ms < ?', [cutoff])
          @db.changes
        end
      end

      # Record a logical-idempotency outcome (§6.4).
      #
      # @param session_principal [String]
      # @param idempotency_key [String]
      # @param outcome [Hash]
      # @return [Boolean] true if newly recorded, false if it already existed
      def record_idempotent_outcome(session_principal:, idempotency_key:, outcome:)
        @mutex.synchronize do
          @db.execute(
            INSERT_IDEMPOTENT_SQL,
            [session_principal, idempotency_key, JSON.generate(outcome), clock_ms]
          )
          true
        end
      rescue SQLite3::ConstraintException
        false
      end

      LOOKUP_IDEMPOTENT_SQL = <<~SQL
        SELECT outcome_json FROM arcp_idempotency
        WHERE session_principal = ? AND idempotency_key = ?
      SQL
      private_constant :LOOKUP_IDEMPOTENT_SQL

      INSERT_IDEMPOTENT_SQL = <<~SQL
        INSERT INTO arcp_idempotency (session_principal, idempotency_key, outcome_json, created_at_ms)
        VALUES (?, ?, ?, ?)
      SQL
      private_constant :INSERT_IDEMPOTENT_SQL

      # @return [Hash, nil]
      def lookup_idempotent_outcome(session_principal:, idempotency_key:)
        @mutex.synchronize do
          row = @db.get_first_row(LOOKUP_IDEMPOTENT_SQL, [session_principal, idempotency_key])
          row && JSON.parse(row['outcome_json'], symbolize_names: true)
        end
      end

      # Close the underlying SQLite connection.
      def close
        @mutex.synchronize { @db.close unless @db.closed? }
      end

      private

      def clock_ms
        (@clock.now.to_f * 1000).to_i
      end

      def build_replay_filter(after_seq:, session_id:, job_id:, stream_id:, trace_id:, types:)
        clauses = []
        params = []
        if after_seq
          clauses << 'monotonic_seq > ?'
          params << after_seq
        end
        if session_id
          clauses << 'session_id = ?'
          params << session_id
        end
        if job_id
          clauses << 'job_id = ?'
          params << job_id
        end
        if stream_id
          clauses << 'stream_id = ?'
          params << stream_id
        end
        if trace_id
          clauses << 'trace_id = ?'
          params << trace_id
        end
        if types && !types.empty?
          clauses << "type IN (#{(['?'] * types.size).join(',')})"
          params.concat(types)
        end
        [clauses, params]
      end
    end
  end
end
