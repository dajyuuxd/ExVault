// Database schema definitions and migration management for SQLite storage.

import Foundation

public enum Schema {
    public static let v1: [String] = [
        """
        CREATE TABLE nodes (
          id           TEXT PRIMARY KEY,
          parent_id    TEXT REFERENCES nodes(id) ON DELETE CASCADE,
          kind         INTEGER NOT NULL,
          name         TEXT NOT NULL,
          name_lower   TEXT NOT NULL,
          size         INTEGER NOT NULL DEFAULT 0,
          stored_size  INTEGER NOT NULL DEFAULT 0,
          mime         TEXT NOT NULL DEFAULT '',
          codec        INTEGER NOT NULL DEFAULT 0,
          crc32        INTEGER NOT NULL DEFAULT 0,
          blob_id      TEXT,
          has_thumb    INTEGER NOT NULL DEFAULT 0,
          created_at   INTEGER NOT NULL,
          modified_at  INTEGER NOT NULL,
          trashed_at   INTEGER,
          trash_root   TEXT
        );
        """,
        "CREATE INDEX idx_nodes_parent ON nodes(parent_id, trashed_at, kind, name_lower);",
        "CREATE INDEX idx_nodes_name   ON nodes(name_lower);",
        "CREATE INDEX idx_nodes_trash  ON nodes(trashed_at) WHERE trashed_at IS NOT NULL;",
        """
        CREATE TABLE tags (
          id    INTEGER PRIMARY KEY AUTOINCREMENT,
          name  TEXT NOT NULL UNIQUE COLLATE NOCASE,
          color TEXT NOT NULL DEFAULT '#888888'
        );
        """,
        """
        CREATE TABLE node_tags (
          node_id TEXT    NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
          tag_id  INTEGER NOT NULL REFERENCES tags(id)  ON DELETE CASCADE,
          PRIMARY KEY (node_id, tag_id)
        );
        """,
        "CREATE INDEX idx_node_tags_tag ON node_tags(tag_id);",
        """
        CREATE TABLE uploads (
          id          TEXT PRIMARY KEY,
          parent_id   TEXT,
          name        TEXT NOT NULL,
          size        INTEGER NOT NULL,
          received    INTEGER NOT NULL DEFAULT 0,
          crc         INTEGER NOT NULL DEFAULT 0,
          mime        TEXT NOT NULL DEFAULT '',
          mtime       INTEGER,
          compress    INTEGER NOT NULL DEFAULT 1,
          state       TEXT NOT NULL DEFAULT 'receiving',
          node_id     TEXT,
          error       TEXT,
          created_at  INTEGER NOT NULL,
          updated_at  INTEGER NOT NULL
        );
        """
    ]

    /// Migrates database schema to the latest version.
    public static func migrate(_ db: Database) throws {
        let version = try db.scalarInt("PRAGMA user_version;") ?? 0
        if version == 0 {
            try db.transaction {
                for sql in v1 {
                    try db.exec(sql)
                }
                try db.exec("PRAGMA user_version = 1;")
            }
        }
    }
}
