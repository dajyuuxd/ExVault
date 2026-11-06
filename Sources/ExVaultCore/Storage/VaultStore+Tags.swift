// VaultStore extensions for tag management, search indexing, and vault statistics.

import Foundation

public struct Tag: Codable, Equatable {
    public var id: Int64
    public var name: String
    public var color: String

    public init(id: Int64, name: String, color: String) {
        self.id = id
        self.name = name
        self.color = color
    }
}

public struct VaultStats: Codable, Equatable {
    public var fileCount: Int64
    public var folderCount: Int64
    public var totalBytes: Int64
    public var storedBytes: Int64
    public var trashBytes: Int64

    public init(
        fileCount: Int64,
        folderCount: Int64,
        totalBytes: Int64,
        storedBytes: Int64,
        trashBytes: Int64
    ) {
        self.fileCount = fileCount
        self.folderCount = folderCount
        self.totalBytes = totalBytes
        self.storedBytes = storedBytes
        self.trashBytes = trashBytes
    }
}

extension VaultStore {

    // MARK: - Tag Management

    public func listTags() throws -> [Tag] {
        return try db.sync {
            let sql = "SELECT id, name, color FROM tags ORDER BY name COLLATE NOCASE ASC;"
            return try db.query(sql) { row in
                Tag(id: row.int(0), name: row.text(1), color: row.text(2))
            }
        }
    }

    public func createTag(name: String, color: String?) throws -> Tag {
        guard let validName = validateTagName(name) else {
            throw StoreError(code: "invalid_name", message: "Tag name must be 1 to 32 non-control characters")
        }
        let finalColor = color ?? "#888888"
        guard isValidTagColor(finalColor) else {
            throw StoreError(code: "bad_request", message: "Color must be in hex format #rrggbb")
        }

        return try db.sync {
            try db.transaction {
                let count = try db.scalarInt("SELECT count(*) FROM tags WHERE name = ? COLLATE NOCASE;", [.text(validName)]) ?? 0
                if count > 0 {
                    throw StoreError(code: "name_conflict", message: "Tag name already exists")
                }
                try db.run("INSERT INTO tags (name, color) VALUES (?, ?);", [.text(validName), .text(finalColor)])
                let newId = db.lastInsertRowID
                return Tag(id: newId, name: validName, color: finalColor)
            }
        }
    }

    public func updateTag(id: Int64, name: String?, color: String?) throws -> Tag {
        return try db.sync {
            try db.transaction {
                let tags = try db.query("SELECT id, name, color FROM tags WHERE id = ?;", [.int(id)]) {
                    Tag(id: $0.int(0), name: $0.text(1), color: $0.text(2))
                }
                guard var current = tags.first else {
                    throw StoreError(code: "not_found", message: "Tag not found")
                }

                if let rawName = name {
                    guard let validName = validateTagName(rawName) else {
                        throw StoreError(code: "invalid_name", message: "Tag name must be 1 to 32 non-control characters")
                    }
                    let count = try db.scalarInt("SELECT count(*) FROM tags WHERE name = ? COLLATE NOCASE AND id != ?;", [.text(validName), .int(id)]) ?? 0
                    if count > 0 {
                        throw StoreError(code: "name_conflict", message: "Tag name already exists")
                    }
                    current.name = validName
                }

                if let rawColor = color {
                    guard isValidTagColor(rawColor) else {
                        throw StoreError(code: "bad_request", message: "Color must be in hex format #rrggbb")
                    }
                    current.color = rawColor
                }

                try db.run("UPDATE tags SET name = ?, color = ? WHERE id = ?;", [.text(current.name), .text(current.color), .int(id)])
                return current
            }
        }
    }

    public func deleteTag(id: Int64) throws {
        try db.sync {
            try db.transaction {
                try db.run("DELETE FROM tags WHERE id = ?;", [.int(id)])
            }
        }
    }

    public func applyTags(ids: [String], add: [Int64], remove: [Int64]) throws -> [Node] {
        return try db.sync {
            try db.transaction {
                // Filter valid existing tags to add
                var validAdd: [Int64] = []
                for tid in add {
                    let exists = try db.scalarInt("SELECT count(*) FROM tags WHERE id = ?;", [.int(tid)]) ?? 0
                    if exists > 0 {
                        validAdd.append(tid)
                    }
                }

                for nid in ids {
                    let alive = try db.scalarInt("SELECT count(*) FROM nodes WHERE id = ? AND trashed_at IS NULL;", [.text(nid)]) ?? 0
                    if alive == 0 {
                        continue
                    }
                    for tid in validAdd {
                        try db.run("INSERT OR IGNORE INTO node_tags (node_id, tag_id) VALUES (?, ?);", [.text(nid), .int(tid)])
                    }
                    for tid in remove {
                        try db.run("DELETE FROM node_tags WHERE node_id = ? AND tag_id = ?;", [.text(nid), .int(tid)])
                    }
                }

                var resultNodes: [Node] = []
                for nid in ids {
                    if let node = try getNode(nid), node.trashedAt == nil {
                        resultNodes.append(node)
                    }
                }
                return resultNodes
            }
        }
    }

    // MARK: - Search

    public func search(q: String?, tagId: Int64?, limit: Int = 500) throws -> [(node: Node, pathText: String)] {
        let trimmedQ = q?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasQuery = trimmedQ != nil && !(trimmedQ?.isEmpty ?? true)
        let hasTag = tagId != nil

        guard hasQuery || hasTag else {
            throw StoreError(code: "bad_request", message: "Search requires query text or tagId")
        }

        return try db.sync {
            var binds: [SQLValue] = []
            var joinClause = ""
            var whereClauses = ["n.trashed_at IS NULL"]

            if let tid = tagId {
                joinClause = "JOIN node_tags nt ON n.id = nt.node_id AND nt.tag_id = ?"
                binds.append(.int(tid))
            }

            if let queryText = trimmedQ, !queryText.isEmpty {
                let escaped = escapeLike(queryText.lowercased())
                whereClauses.append("n.name_lower LIKE ? ESCAPE '\\'")
                binds.append(.text("%\(escaped)%"))
            }

            let maxResults = min(max(limit, 1), 500)
            let sql = """
            SELECT n.id, n.parent_id, n.kind, n.name, n.size, n.stored_size, n.mime, n.codec, n.has_thumb, n.created_at, n.modified_at, n.trashed_at
            FROM nodes n
            \(joinClause)
            WHERE \(whereClauses.joined(separator: " AND "))
            ORDER BY n.kind ASC, n.name_lower ASC, n.id ASC
            LIMIT \(maxResults);
            """

            var nodes = try db.query(sql, binds) { row in
                Node(
                    id: row.text(0),
                    parentId: row.optText(1),
                    kind: row.int(2) == 0 ? "folder" : "file",
                    name: row.text(3),
                    size: row.int(4),
                    storedSize: row.int(5),
                    mime: row.text(6),
                    codec: row.int(7) == 1 ? "zlib" : "raw",
                    hasThumb: row.int(8) != 0,
                    tagIds: [],
                    createdAt: row.int(9),
                    modifiedAt: row.int(10),
                    trashedAt: row.optInt(11)
                )
            }

            // Attach tags
            try self.attachTags(to: &nodes)

            // Build pathText
            var pathCache: [String?: String] = [nil: "/"]
            var results: [(node: Node, pathText: String)] = []
            for node in nodes {
                let path: String
                if let cached = pathCache[node.parentId] {
                    path = cached
                } else {
                    let crumbs = try breadcrumb(of: node.parentId)
                    let built = "/" + crumbs.map { $0.name }.joined(separator: "/")
                    pathCache[node.parentId] = built
                    path = built
                }
                results.append((node: node, pathText: path))
            }

            return results
        }
    }

    // MARK: - Vault Statistics

    public func stats() throws -> VaultStats {
        return try db.sync {
            let fileCount = try db.scalarInt("SELECT count(*) FROM nodes WHERE kind = 1 AND trashed_at IS NULL;") ?? 0
            let folderCount = try db.scalarInt("SELECT count(*) FROM nodes WHERE kind = 0 AND trashed_at IS NULL;") ?? 0
            let totalBytes = try db.scalarInt("SELECT COALESCE(SUM(size), 0) FROM nodes WHERE kind = 1 AND trashed_at IS NULL;") ?? 0
            let storedBytes = try db.scalarInt("SELECT COALESCE(SUM(stored_size), 0) FROM nodes WHERE kind = 1 AND trashed_at IS NULL;") ?? 0
            let trashBytes = try db.scalarInt("SELECT COALESCE(SUM(stored_size), 0) FROM nodes WHERE kind = 1 AND trashed_at IS NOT NULL;") ?? 0

            return VaultStats(
                fileCount: fileCount,
                folderCount: folderCount,
                totalBytes: totalBytes,
                storedBytes: storedBytes,
                trashBytes: trashBytes
            )
        }
    }

    // MARK: - Helper Methods

    private func validateTagName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.count > 32 {
            return nil
        }
        for scalar in trimmed.unicodeScalars {
            if scalar.value <= 0x1F || scalar.value == 0x7F {
                return nil
            }
        }
        return trimmed
    }

    private func isValidTagColor(_ color: String) -> Bool {
        guard color.count == 7, color.hasPrefix("#") else { return false }
        let hex = color.dropFirst()
        let hexChars = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        return hex.unicodeScalars.allSatisfy { hexChars.contains($0) }
    }

    private func escapeLike(_ s: String) -> String {
        var out = ""
        for ch in s {
            if ch == "\\" || ch == "%" || ch == "_" {
                out.append("\\")
            }
            out.append(ch)
        }
        return out
    }
}
