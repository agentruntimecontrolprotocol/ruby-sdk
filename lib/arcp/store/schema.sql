CREATE TABLE IF NOT EXISTS arcp_events (
  monotonic_seq    INTEGER PRIMARY KEY AUTOINCREMENT,
  message_id       TEXT    NOT NULL UNIQUE,
  type             TEXT    NOT NULL,
  session_id       TEXT,
  job_id           TEXT,
  stream_id        TEXT,
  subscription_id  TEXT,
  trace_id         TEXT,
  priority         TEXT    NOT NULL DEFAULT 'normal',
  timestamp        TEXT    NOT NULL,
  envelope_json    TEXT    NOT NULL,
  inserted_at_ms   INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_arcp_events_session  ON arcp_events(session_id, monotonic_seq);
CREATE INDEX IF NOT EXISTS idx_arcp_events_job      ON arcp_events(job_id, monotonic_seq);
CREATE INDEX IF NOT EXISTS idx_arcp_events_stream   ON arcp_events(stream_id, monotonic_seq);
CREATE INDEX IF NOT EXISTS idx_arcp_events_trace    ON arcp_events(trace_id, monotonic_seq);
CREATE INDEX IF NOT EXISTS idx_arcp_events_type     ON arcp_events(type, monotonic_seq);
CREATE INDEX IF NOT EXISTS idx_arcp_events_inserted ON arcp_events(inserted_at_ms);

CREATE TABLE IF NOT EXISTS arcp_artifacts (
  artifact_id   TEXT PRIMARY KEY,
  session_id    TEXT,
  media_type    TEXT,
  size          INTEGER NOT NULL,
  sha256        TEXT,
  data          BLOB    NOT NULL,
  expires_at_ms INTEGER,
  created_at_ms INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_arcp_artifacts_expires ON arcp_artifacts(expires_at_ms);

CREATE TABLE IF NOT EXISTS arcp_idempotency (
  session_principal TEXT NOT NULL,
  idempotency_key   TEXT NOT NULL,
  outcome_json      TEXT NOT NULL,
  created_at_ms     INTEGER NOT NULL,
  PRIMARY KEY (session_principal, idempotency_key)
);
