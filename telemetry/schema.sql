PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS sessions (
    session_id TEXT PRIMARY KEY,
    player_id TEXT,
    player_name TEXT NOT NULL DEFAULT '',
    game_version TEXT NOT NULL DEFAULT '',
    started_at REAL NOT NULL,
    last_seen REAL NOT NULL,
    ended_at REAL,
    outcome TEXT
);

CREATE TABLE IF NOT EXISTS events (
    event_id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL REFERENCES sessions(session_id),
    seq INTEGER NOT NULL,
    kind TEXT NOT NULL,
    ts REAL NOT NULL,
    elapsed REAL NOT NULL DEFAULT 0,
    level INTEGER NOT NULL DEFAULT 0,
    x REAL,
    y REAL,
    z REAL,
    data_json TEXT NOT NULL DEFAULT '{}'
);
CREATE INDEX IF NOT EXISTS events_session_order ON events(session_id, seq, ts);
CREATE INDEX IF NOT EXISTS events_session_level ON events(session_id, level);
CREATE INDEX IF NOT EXISTS events_kind ON events(kind);

-- Byte offsets only advance past complete newline-terminated records.
CREATE TABLE IF NOT EXISTS ingestion_sources (
    source TEXT PRIMARY KEY,
    byte_offset INTEGER NOT NULL DEFAULT 0,
    imported_count INTEGER NOT NULL DEFAULT 0,
    rejected_count INTEGER NOT NULL DEFAULT 0
);
PRAGMA user_version = 1;
