// Vault metadata store managing nodes, hierarchy, trash, restore, and purge operations.

import Foundation

public struct Node: Codable, Equatable {
    public var id: String
    public var parentId: String?
    public var kind: String // "folder" | "file"
    public var name: String
    public var size: Int64
    public var storedSize: Int64
    public var mime: String
    public var codec: String // "raw" | "zlib"
    public var hasThumb: Bool
    public var tagIds: [Int64]
    public var createdAt: Int64
    public var modifiedAt: Int64
    public var trashedAt: Int64?

    public init(
        id: String,
        parentId: String?,
        kind: String,
        name: String,
        size: Int64,
        storedSize: Int64,
        mime: String,
        codec: String,
        hasThumb: Bool,
        tagIds: [Int64],
        createdAt: Int64,
        modifiedAt: Int64,
        trashedAt: Int64?
    ) {
        self.id = id
        self.parentId = parentId
        self.kind = kind
        self.name = name
        self.size = size
        self.storedSize = storedSize
        self.mime = mime
        self.codec = codec
        self.hasThumb = hasThumb
        self.tagIds = tagIds
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.trashedAt = trashedAt
    }
}

public enum SortKey: String {
    case name
    case size
    case date
    case type
}

public enum SortOrder: String {
    case asc
    case desc
}

public struct StoreError: Error, CustomStringConvertible {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }

    public var description: String {
        return "StoreError(\(code): \(message))"
    }
}

public final class VaultStore {
    private let db: Database
    public static var nowMs: () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }

    public init(db: Database) {
        self.db = db
    }

    public func getNode(_ id: String) throws -> Node? {
        return try db.sync {
            try getNodeDirect(id)
        }
    }

    private func getNodeDirect(_ id: String) throws -> Node? {
        let sql = """
        SELECT id, parent_id, kind, name, size, stored_size, mime, codec, has_thumb, created_at, modified_at, trashed_at
        FROM nodes WHERE id = ?;
        """
        let nodes = try db.query(sql, [.text(id)]) { row in
            mapNode(row, tagIds: [])
        }
        guard var node = nodes.first else {
            return nil
        }
        let tags = try db.query("SELECT tag_id FROM node_tags WHERE node_id = ? ORDER BY tag_id ASC;", [.text(id)]) { $0.int(0) }
        node.tagIds = tags
        return node
    }

    public func listChildren(parentId: String?, sort: SortKey, order: SortOrder) throws -> [Node] {
        return try db.sync {
            let parentBind: SQLValue = parentId.map { .text($0) } ?? .null
            let orderDir = (order == .desc) ? "DESC" : "ASC"

            let orderByClause: String
            switch sort {
            case .name:
                orderByClause = "ORDER BY kind ASC, name_lower \(orderDir), id ASC"
            case .size:
                orderByClause = "ORDER BY kind ASC, size \(orderDir), name_lower ASC, id ASC"
            case .date:
                orderByClause = "ORDER BY kind ASC, modified_at \(orderDir), name_lower ASC, id ASC"
            case .type:
                // Extension sorting is applied stably in Swift; SQL orders folders first then names
                orderByClause = "ORDER BY kind ASC, name_lower ASC, id ASC"
            }

            let sql = """
            SELECT id, parent_id, kind, name, size, stored_size, mime, codec, has_thumb, created_at, modified_at, trashed_at
            FROM nodes
            WHERE parent_id IS ? AND trashed_at IS NULL
            \(orderByClause);
            """

            var nodes = try db.query(sql, [parentBind]) { row in
                mapNode(row, tagIds: [])
            }

            if sort == .type {
                // Stable sort by extension inside files group
                nodes.sort { a, b in
                    if a.kind != b.kind {
                        return a.kind == "folder"
                    }
                    if a.kind == "folder" {
                        return a.name.lowercased() < b.name.lowercased()
                    }
                    let extA = NameRules.splitExt(a.name).ext.lowercased()
                    let extB = NameRules.splitExt(b.name).ext.lowercased()
                    if extA != extB {
                        return order == .desc ? extA > extB : extA < extB
                    }
                    return a.name.lowercased() < b.name.lowercased()
                }
            }

            try attachTags(to: &nodes)
            return nodes
        }
    }

    public func breadcrumb(of id: String?) throws -> [(id: String, name: String)] {
        guard let startId = id else {
            return []
        }
        return try db.sync {
            var crumbs: [(id: String, name: String)] = []
            var currentId: String? = startId
            var visited = Set<String>()
            while let cid = currentId {
                if visited.contains(cid) { break }
                visited.insert(cid)
                let rows = try db.query("SELECT parent_id, name FROM nodes WHERE id = ?;", [.text(cid)]) { ($0.optText(0), $0.text(1)) }
                guard let first = rows.first else { break }
                crumbs.append((id: cid, name: first.1))
                currentId = first.0
            }
            return crumbs.reversed()
        }
    }

    public func createFolder(parentId: String?, name: String) throws -> Node {
        guard let validName = NameRules.validate(name) else {
            throw StoreError(code: "invalid_name", message: "Invalid folder name")
        }
        return try db.sync {
            try db.transaction {
                guard try nodeExistsAliveFolder(parentId) else {
                    throw StoreError(code: "not_found", message: "Parent folder not found")
                }
                let existing = try siblingLowerNames(parentId: parentId)
                let unique = NameRules.uniqueName(validName) { existing.contains($0.lowercased()) }
                let newId = IDGen.newID()
                let now = VaultStore.nowMs()

                try db.run(
                    """
                    INSERT INTO nodes (id, parent_id, kind, name, name_lower, size, stored_size, mime, codec, crc32, blob_id, has_thumb, created_at, modified_at, trashed_at, trash_root)
                    VALUES (?, ?, 0, ?, ?, 0, 0, '', 0, 0, NULL, 0, ?, ?, NULL, NULL);
                    """,
                    [
                        .text(newId),
                        parentId.map { .text($0) } ?? .null,
                        .text(unique),
                        .text(unique.lowercased()),
                        .int(now),
                        .int(now)
                    ]
                )

                return Node(
                    id: newId,
                    parentId: parentId,
                    kind: "folder",
                    name: unique,
                    size: 0,
                    storedSize: 0,
                    mime: "",
                    codec: "raw",
                    hasThumb: false,
                    tagIds: [],
                    createdAt: now,
                    modifiedAt: now,
                    trashedAt: nil
                )
            }
        }
    }

    public func createFile(
        parentId: String?,
        name: String,
        size: Int64,
        storedSize: Int64,
        mime: String,
        codec: Int,
        crc32: UInt32,
        blobId: String,
        mtime: Int64?
    ) throws -> Node {
        guard let validName = NameRules.validate(name) else {
            throw StoreError(code: "invalid_name", message: "Invalid file name")
        }
        return try db.sync {
            try db.transaction {
                var targetParent = parentId
                if !(try nodeExistsAliveFolder(targetParent)) {
                    targetParent = nil
                }
                let existing = try siblingLowerNames(parentId: targetParent)
                let unique = NameRules.uniqueName(validName) { existing.contains($0.lowercased()) }
                let newId = IDGen.newID()
                let now = VaultStore.nowMs()
                let fileTime = mtime ?? now

                try db.run(
                    """
                    INSERT INTO nodes (id, parent_id, kind, name, name_lower, size, stored_size, mime, codec, crc32, blob_id, has_thumb, created_at, modified_at, trashed_at, trash_root)
                    VALUES (?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, NULL, NULL);
                    """,
                    [
                        .text(newId),
                        targetParent.map { .text($0) } ?? .null,
                        .text(unique),
                        .text(unique.lowercased()),
                        .int(size),
                        .int(storedSize),
                        .text(mime),
                        .int(Int64(codec)),
                        .int(Int64(crc32)),
                        .text(blobId),
                        .int(fileTime),
                        .int(fileTime)
                    ]
                )

                return Node(
                    id: newId,
                    parentId: targetParent,
                    kind: "file",
                    name: unique,
                    size: size,
                    storedSize: storedSize,
                    mime: mime,
                    codec: codec == 1 ? "zlib" : "raw",
                    hasThumb: false,
                    tagIds: [],
                    createdAt: fileTime,
                    modifiedAt: fileTime,
                    trashedAt: nil
                )
            }
        }
    }

    public func fileBlobInfo(_ id: String) throws -> (blobId: String, codec: Int, size: Int64, storedSize: Int64, crc32: UInt32, mime: String, name: String)? {
        return try db.sync {
            let sql = """
            SELECT blob_id, codec, size, stored_size, crc32, mime, name
            FROM nodes WHERE id = ? AND kind = 1 AND trashed_at IS NULL;
            """
            let rows = try db.query(sql, [.text(id)]) { row -> (String, Int, Int64, Int64, UInt32, String, String)? in
                guard let bId = row.optText(0) else { return nil }
                return (
                    bId,
                    Int(row.int(1)),
                    row.int(2),
                    row.int(3),
                    UInt32(row.int(4) & 0xFFFFFFFF),
                    row.text(5),
                    row.text(6)
                )
            }
            return rows.first ?? nil
        }
    }

    public func rename(_ id: String, to newName: String) throws -> Node {
        guard let validName = NameRules.validate(newName) else {
            throw StoreError(code: "invalid_name", message: "Invalid name")
        }
        return try db.sync {
            try db.transaction {
                guard var node = try getNodeDirect(id), node.trashedAt == nil else {
                    throw StoreError(code: "not_found", message: "Node not found")
                }
                let targetLower = validName.lowercased()
                let parentBind: SQLValue = node.parentId.map { .text($0) } ?? .null

                // Check conflict with other alive siblings
                let conflicts = try db.scalarInt(
                    "SELECT count(*) FROM nodes WHERE parent_id IS ? AND trashed_at IS NULL AND name_lower = ? AND id != ?;",
                    [parentBind, .text(targetLower), .text(id)]
                ) ?? 0
                if conflicts > 0 {
                    throw StoreError(code: "name_conflict", message: "Name conflict in current folder")
                }

                let now = VaultStore.nowMs()
                try db.run(
                    "UPDATE nodes SET name = ?, name_lower = ?, modified_at = ? WHERE id = ?;",
                    [.text(validName), .text(targetLower), .int(now), .text(id)]
                )

                node.name = validName
                node.modifiedAt = now
                return node
            }
        }
    }

    public func move(_ ids: [String], to parentId: String?) throws -> [Node] {
        return try db.sync {
            try db.transaction {
                guard try nodeExistsAliveFolder(parentId) else {
                    throw StoreError(code: "invalid_move", message: "Destination is not a valid folder")
                }

                var movedNodes: [Node] = []
                for id in ids {
                    guard var node = try getNodeDirect(id), node.trashedAt == nil else {
                        continue
                    }
                    if node.parentId == parentId {
                        movedNodes.append(node)
                        continue
                    }

                    if node.kind == "folder" {
                        if parentId == id {
                            throw StoreError(code: "invalid_move", message: "Cannot move folder into itself")
                        }
                        if let pid = parentId, try isDescendant(candidateDescendantId: pid, ancestorId: id) {
                            throw StoreError(code: "invalid_move", message: "Cannot move folder into its own descendant")
                        }
                    }

                    let siblings = try siblingLowerNames(parentId: parentId)
                    let unique = NameRules.uniqueName(node.name) { siblings.contains($0.lowercased()) }
                    let now = VaultStore.nowMs()

                    try db.run(
                        "UPDATE nodes SET parent_id = ?, name = ?, name_lower = ?, modified_at = ? WHERE id = ?;",
                        [
                            parentId.map { .text($0) } ?? .null,
                            .text(unique),
                            .text(unique.lowercased()),
                            .int(now),
                            .text(id)
                        ]
                    )

                    node.parentId = parentId
                    node.name = unique
                    node.modifiedAt = now
                    movedNodes.append(node)
                }
                return movedNodes
            }
        }
    }

    public func trash(_ ids: [String]) throws -> Int {
        return try db.sync {
            try db.transaction {
                var total = 0
                let now = VaultStore.nowMs()
                for id in ids {
                    let alive = try db.scalarInt("SELECT count(*) FROM nodes WHERE id = ? AND trashed_at IS NULL;", [.text(id)]) ?? 0
                    if alive == 0 {
                        continue
                    }

                    let sql = """
                    WITH RECURSIVE d(id) AS (
                        SELECT ?
                        UNION ALL
                        SELECT n.id FROM nodes n JOIN d ON n.parent_id = d.id
                    )
                    UPDATE nodes
                    SET trashed_at = ?, trash_root = ?
                    WHERE id IN (SELECT id FROM d) AND trashed_at IS NULL;
                    """
                    let changed = try db.run(sql, [.text(id), .int(now), .text(id)])
                    if changed > 0 {
                        total += 1
                    }
                }
                return total
            }
        }
    }

    public func restore(_ ids: [String]) throws -> Int {
        return try db.sync {
            try db.transaction {
                var total = 0
                for rootId in ids {
                    let rootNodeRows = try db.query("SELECT parent_id, name FROM nodes WHERE id = ? AND trash_root = ?;", [.text(rootId), .text(rootId)]) {
                        ($0.optText(0), $0.text(1))
                    }
                    guard let rootInfo = rootNodeRows.first else {
                        continue
                    }

                    var targetParent = rootInfo.0
                    if !(try nodeExistsAliveFolder(targetParent)) {
                        targetParent = nil
                    }

                    let siblings = try siblingLowerNames(parentId: targetParent)
                    let unique = NameRules.uniqueName(rootInfo.1) { siblings.contains($0.lowercased()) }

                    try db.run(
                        "UPDATE nodes SET parent_id = ?, name = ?, name_lower = ? WHERE id = ?;",
                        [
                            targetParent.map { .text($0) } ?? .null,
                            .text(unique),
                            .text(unique.lowercased()),
                            .text(rootId)
                        ]
                    )

                    let updated = try db.run(
                        "UPDATE nodes SET trashed_at = NULL, trash_root = NULL WHERE trash_root = ?;",
                        [.text(rootId)]
                    )
                    if updated > 0 {
                        total += 1
                    }
                }
                return total
            }
        }
    }

    public func purge(_ ids: [String]) throws -> (count: Int, blobIds: [String], thumbNodeIds: [String]) {
        return try db.sync {
            try db.transaction {
                var totalCount = 0
                var allBlobIds: [String] = []
                var allThumbIds: [String] = []

                for rootId in ids {
                    // Check that it is a valid trash root
                    let isTrashRoot = try db.scalarInt("SELECT count(*) FROM nodes WHERE id = ? AND trash_root = ?;", [.text(rootId), .text(rootId)]) ?? 0
                    if isTrashRoot == 0 {
                        continue
                    }

                    let blobs = try db.query(
                        "SELECT blob_id FROM nodes WHERE trash_root = ? AND kind = 1 AND blob_id IS NOT NULL;",
                        [.text(rootId)]
                    ) { $0.text(0) }
                    allBlobIds.append(contentsOf: blobs)

                    let thumbs = try db.query(
                        "SELECT id FROM nodes WHERE trash_root = ? AND has_thumb = 1;",
                        [.text(rootId)]
                    ) { $0.text(0) }
                    allThumbIds.append(contentsOf: thumbs)

                    let deleted = try db.run("DELETE FROM nodes WHERE id = ? AND trash_root = ?;", [.text(rootId), .text(rootId)])
                    if deleted > 0 {
                        totalCount += 1
                    }
                }
                return (count: totalCount, blobIds: allBlobIds, thumbNodeIds: allThumbIds)
            }
        }
    }

    public func emptyTrash() throws -> (count: Int, blobIds: [String], thumbNodeIds: [String]) {
        return try db.sync {
            let rootIds = try db.query("SELECT id FROM nodes WHERE trash_root = id;") { $0.text(0) }
            return try purge(rootIds)
        }
    }

    public func listTrash() throws -> [Node] {
        return try db.sync {
            let sql = """
            SELECT id, parent_id, kind, name, size, stored_size, mime, codec, has_thumb, created_at, modified_at, trashed_at
            FROM nodes
            WHERE trash_root = id
            ORDER BY trashed_at DESC, modified_at DESC;
            """
            var nodes = try db.query(sql) { row in
                mapNode(row, tagIds: [])
            }
            try attachTags(to: &nodes)
            return nodes
        }
    }

    public func setHasThumb(_ id: String, _ has: Bool) throws {
        try db.sync {
            try db.run("UPDATE nodes SET has_thumb = ? WHERE id = ?;", [.int(has ? 1 : 0), .text(id)])
        }
    }

    public func nodeExistsAliveFolder(_ id: String?) throws -> Bool {
        guard let fid = id else {
            return true
        }
        return try db.sync {
            let kind = try db.scalarInt("SELECT kind FROM nodes WHERE id = ? AND trashed_at IS NULL;", [.text(fid)])
            return kind == 0
        }
    }

    // MARK: - Private Helpers

    private func isDescendant(candidateDescendantId: String, ancestorId: String) throws -> Bool {
        var current: String? = candidateDescendantId
        var visited = Set<String>()
        while let cid = current {
            if cid == ancestorId {
                return true
            }
            if visited.contains(cid) { break }
            visited.insert(cid)
            let parents = try db.query("SELECT parent_id FROM nodes WHERE id = ?;", [.text(cid)]) { $0.optText(0) }
            guard let first = parents.first, let nextParent = first else {
                break
            }
            current = nextParent
        }
        return false
    }

    private func siblingLowerNames(parentId: String?) throws -> Set<String> {
        let parentBind: SQLValue = parentId.map { .text($0) } ?? .null
        let names = try db.query("SELECT name_lower FROM nodes WHERE parent_id IS ? AND trashed_at IS NULL;", [parentBind]) { $0.text(0) }
        return Set(names)
    }

    private func attachTags(to nodes: inout [Node]) throws {
        if nodes.isEmpty { return }
        var idToIndices: [String: [Int]] = [:]
        for (i, node) in nodes.enumerated() {
            idToIndices[node.id, default: []].append(i)
        }

        let nodeIds = nodes.map { $0.id }
        let chunkSize = 500
        var start = 0
        while start < nodeIds.count {
            let end = min(start + chunkSize, nodeIds.count)
            let chunk = Array(nodeIds[start..<end])
            let placeholders = [String](repeating: "?", count: chunk.count).joined(separator: ",")
            let binds = chunk.map { SQLValue.text($0) }
            let sql = "SELECT node_id, tag_id FROM node_tags WHERE node_id IN (\(placeholders)) ORDER BY tag_id ASC;"
            _ = try db.query(sql, binds) { row in
                let nid = row.text(0)
                let tid = row.int(1)
                if let indices = idToIndices[nid] {
                    for idx in indices {
                        nodes[idx].tagIds.append(tid)
                    }
                }
            }
            start = end
        }
    }
}

private func mapNode(_ row: Row, tagIds: [Int64]) -> Node {
    return Node(
        id: row.text(0),
        parentId: row.optText(1),
        kind: row.int(2) == 0 ? "folder" : "file",
        name: row.text(3),
        size: row.int(4),
        storedSize: row.int(5),
        mime: row.text(6),
        codec: row.int(7) == 1 ? "zlib" : "raw",
        hasThumb: row.int(8) != 0,
        tagIds: tagIds,
        createdAt: row.int(9),
        modifiedAt: row.int(10),
        trashedAt: row.optInt(11)
    )
}
