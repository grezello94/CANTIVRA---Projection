/// Every migration is applied in one transaction. A newer database is rejected
/// rather than downgraded or recreated.
const schemaVersion = 2;

const schemaV1 = '''
CREATE TABLE content (
  id TEXT PRIMARY KEY NOT NULL CHECK(length(id) > 0),
  title TEXT NOT NULL CHECK(length(trim(title)) > 0),
  kind TEXT NOT NULL CHECK(kind IN ('hymn','prayer','reading','response','announcement','custom')),
  source_text TEXT NOT NULL,
  language TEXT NOT NULL DEFAULT 'English',
  tags TEXT NOT NULL DEFAULT '[]',
  favorite INTEGER NOT NULL DEFAULT 0 CHECK(favorite IN (0,1)),
  created_at TEXT NOT NULL,
  modified_at TEXT NOT NULL
);
CREATE INDEX content_kind ON content(kind);
CREATE INDEX content_modified ON content(modified_at DESC);

CREATE VIRTUAL TABLE content_fts USING fts5(
  title, source_text, tags,
  content='content', content_rowid='rowid',
  tokenize='unicode61 remove_diacritics 2', prefix='2 3 4'
);
CREATE TRIGGER content_ai AFTER INSERT ON content BEGIN
  INSERT INTO content_fts(rowid,title,source_text,tags)
  VALUES (new.rowid,new.title,new.source_text,new.tags);
END;
CREATE TRIGGER content_ad AFTER DELETE ON content BEGIN
  INSERT INTO content_fts(content_fts,rowid,title,source_text,tags)
  VALUES ('delete',old.rowid,old.title,old.source_text,old.tags);
END;
CREATE TRIGGER content_au AFTER UPDATE ON content BEGIN
  INSERT INTO content_fts(content_fts,rowid,title,source_text,tags)
  VALUES ('delete',old.rowid,old.title,old.source_text,old.tags);
  INSERT INTO content_fts(rowid,title,source_text,tags)
  VALUES (new.rowid,new.title,new.source_text,new.tags);
END;

CREATE TABLE content_versions (
  revision INTEGER PRIMARY KEY AUTOINCREMENT,
  content_id TEXT NOT NULL REFERENCES content(id),
  snapshot_json TEXT NOT NULL,
  saved_at TEXT NOT NULL
);
CREATE INDEX content_versions_item ON content_versions(content_id,revision DESC);

CREATE TABLE services (
  id TEXT PRIMARY KEY NOT NULL CHECK(length(id) > 0),
  title TEXT NOT NULL CHECK(length(trim(title)) > 0),
  modified_at TEXT NOT NULL
);
CREATE TABLE service_items (
  id TEXT NOT NULL CHECK(length(id) > 0),
  service_id TEXT NOT NULL REFERENCES services(id) ON DELETE CASCADE,
  content_id TEXT NOT NULL REFERENCES content(id) ON DELETE RESTRICT,
  label TEXT NOT NULL,
  position INTEGER NOT NULL CHECK(position >= 0),
  PRIMARY KEY(service_id,id),
  UNIQUE(service_id,position)
);
CREATE INDEX service_items_content ON service_items(content_id);

CREATE TABLE settings (
  key TEXT PRIMARY KEY NOT NULL,
  value TEXT NOT NULL
);
CREATE TABLE usage_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  content_id TEXT REFERENCES content(id),
  event_type TEXT NOT NULL,
  occurred_at TEXT NOT NULL
);
CREATE INDEX usage_events_content ON usage_events(content_id,occurred_at DESC);
''';

/// Structure is a separate, reversible projection of the original source. The
/// recovery journal accepts even incomplete edits (for example an empty title)
/// without weakening the constraints on the stable content library.
const schemaV2 = '''
ALTER TABLE content ADD COLUMN structure_json TEXT;
CREATE TABLE content_drafts (
  content_id TEXT PRIMARY KEY NOT NULL REFERENCES content(id) ON DELETE CASCADE,
  snapshot_json TEXT NOT NULL,
  modified_at TEXT NOT NULL,
  journaled_at TEXT NOT NULL
);
''';
