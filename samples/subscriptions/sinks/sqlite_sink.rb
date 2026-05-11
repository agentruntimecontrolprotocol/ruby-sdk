# frozen_string_literal: true

# SQLite replay sink. Reuses the SDK's `Arcp::Store::EventLog` schema.
class SQLiteSink
  def self.open(path:)
    sink = new(path: path)
    yield sink
  end

  def initialize(path:)
    @path = path
    # Real version: open sqlite3 connection + execute schema from
    # Arcp::Store::EventLog.
  end

  def handle(_event)
    # Drops kind: thought to keep replay store small.
    # Real version: INSERT OR IGNORE on (id, ts, type, json).
    raise NotImplementedError
  end
end
