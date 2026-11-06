// Tests for SQLite Database wrapper, schema migration, prepared statement binding, and transactions.

import XCTest
@testable import ExVaultCore

final class DatabaseTests: XCTestCase {
    private var tempDbPath: String = ""

    override func setUp() {
        super.setUp()
        tempDbPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("exvault_test_\(UUID().uuidString).db")
    }

    override func tearDown() {
        if !tempDbPath.isEmpty && FileManager.default.fileExists(atPath: tempDbPath) {
            try? FileManager.default.removeItem(atPath: tempDbPath)
            try? FileManager.default.removeItem(atPath: tempDbPath + "-wal")
            try? FileManager.default.removeItem(atPath: tempDbPath + "-shm")
        }
        super.tearDown()
    }

    func testSchemaMigrationAndReopen() throws {
        let db = try Database(path: tempDbPath)
        let version = try db.scalarInt("PRAGMA user_version;")
        XCTAssertEqual(version, 1)

        // Verify tables exist
        let tables = try db.query("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;") { row in
            row.text(0)
        }
        XCTAssertTrue(tables.contains("nodes"))
        XCTAssertTrue(tables.contains("tags"))
        XCTAssertTrue(tables.contains("node_tags"))
        XCTAssertTrue(tables.contains("uploads"))

        // Reopen database file and verify version is maintained
        let reopened = try Database(path: tempDbPath)
        let reopenedVersion = try reopened.scalarInt("PRAGMA user_version;")
        XCTAssertEqual(reopenedVersion, 1)
    }

    func testInsertAndSelectWithBinds() throws {
        let db = try Database(path: tempDbPath)

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let quoteAndEmoji = "Tài liệu 'bí mật' 📁 & \"nháy kép\""

        let inserted = try db.run(
            """
            INSERT INTO nodes (id, parent_id, kind, name, name_lower, size, stored_size, mime, codec, crc32, blob_id, has_thumb, created_at, modified_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            [
                .text("node001"),
                .null,
                .int(1),
                .text(quoteAndEmoji),
                .text(quoteAndEmoji.lowercased()),
                .int(1024),
                .int(512),
                .text("application/pdf"),
                .int(1),
                .int(0x12345678),
                .text("blob001"),
                .int(0),
                .int(now),
                .int(now)
            ]
        )
        XCTAssertEqual(inserted, 1)

        struct NodeRow {
            let id: String
            let parentId: String?
            let name: String
            let size: Int64
            let blobId: String?
        }

        let rows = try db.query("SELECT id, parent_id, name, size, blob_id FROM nodes WHERE id = ?;", [.text("node001")]) { row in
            NodeRow(
                id: row.text(0),
                parentId: row.optText(1),
                name: row.text(2),
                size: row.int(3),
                blobId: row.optText(4)
            )
        }

        XCTAssertEqual(rows.count, 1)
        guard let first = rows.first else {
            XCTFail("No row returned")
            return
        }
        XCTAssertEqual(first.id, "node001")
        XCTAssertNil(first.parentId)
        XCTAssertEqual(first.name, quoteAndEmoji)
        XCTAssertEqual(first.size, 1024)
        XCTAssertEqual(first.blobId, "blob001")
    }

    func testNullHandling() throws {
        let db = try Database(path: tempDbPath)
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        try db.run(
            """
            INSERT INTO nodes (id, parent_id, kind, name, name_lower, size, stored_size, mime, codec, crc32, blob_id, has_thumb, created_at, modified_at, trashed_at, trash_root)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            [
                .text("folder001"),
                .null,
                .int(0),
                .text("Folder"),
                .text("folder"),
                .int(0),
                .int(0),
                .text(""),
                .int(0),
                .int(0),
                .null,
                .int(0),
                .int(now),
                .int(now),
                .null,
                .null
            ]
        )

        let result = try db.query("SELECT blob_id, trashed_at, name FROM nodes WHERE id = ?;", [.text("folder001")]) { row in
            (
                blobIsNull: row.isNull(0),
                blobOpt: row.optText(0),
                trashedOpt: row.optInt(1),
                nameDefault: row.text(2)
            )
        }

        guard let item = result.first else {
            XCTFail("Query failed")
            return
        }
        XCTAssertTrue(item.blobIsNull)
        XCTAssertNil(item.blobOpt)
        XCTAssertNil(item.trashedOpt)
        XCTAssertEqual(item.nameDefault, "Folder")
    }

    func testTransactionRollbackOnError() throws {
        let db = try Database(path: tempDbPath)
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        enum SimulatedError: Error {
            case fail
        }

        do {
            try db.transaction {
                try db.run(
                    """
                    INSERT INTO nodes (id, parent_id, kind, name, name_lower, created_at, modified_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?);
                    """,
                    [.text("temp_node"), .null, .int(0), .text("Temp"), .text("temp"), .int(now), .int(now)]
                )
                throw SimulatedError.fail
            }
            XCTFail("Transaction should have thrown")
        } catch SimulatedError.fail {
            // Expected error
        }

        let count = try db.scalarInt("SELECT count(*) FROM nodes WHERE id = ?;", [.text("temp_node")])
        XCTAssertEqual(count, 0)
    }

    func testForeignKeyCascade() throws {
        let db = try Database(path: tempDbPath)
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        // Insert parent folder
        try db.run(
            """
            INSERT INTO nodes (id, parent_id, kind, name, name_lower, created_at, modified_at)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """,
            [.text("parent_folder"), .null, .int(0), .text("Parent"), .text("parent"), .int(now), .int(now)]
        )

        // Insert child file
        try db.run(
            """
            INSERT INTO nodes (id, parent_id, kind, name, name_lower, created_at, modified_at)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """,
            [.text("child_file"), .text("parent_folder"), .int(1), .text("Child"), .text("child"), .int(now), .int(now)]
        )

        // Insert tag
        try db.run("INSERT INTO tags (name, color) VALUES (?, ?);", [.text("Important"), .text("#ff0000")])
        let tagId = db.lastInsertRowID
        XCTAssertGreaterThan(tagId, 0)

        // Link child to tag
        try db.run("INSERT INTO node_tags (node_id, tag_id) VALUES (?, ?);", [.text("child_file"), .int(tagId)])

        // Verify initial setup
        let childBefore = try db.scalarInt("SELECT count(*) FROM nodes WHERE id = ?;", [.text("child_file")])
        let nodeTagBefore = try db.scalarInt("SELECT count(*) FROM node_tags WHERE node_id = ?;", [.text("child_file")])
        XCTAssertEqual(childBefore, 1)
        XCTAssertEqual(nodeTagBefore, 1)

        // Delete parent folder
        try db.run("DELETE FROM nodes WHERE id = ?;", [.text("parent_folder")])

        // Verify child node and node_tags were cascade deleted
        let childAfter = try db.scalarInt("SELECT count(*) FROM nodes WHERE id = ?;", [.text("child_file")])
        let nodeTagAfter = try db.scalarInt("SELECT count(*) FROM node_tags WHERE node_id = ?;", [.text("child_file")])
        XCTAssertEqual(childAfter, 0)
        XCTAssertEqual(nodeTagAfter, 0)

        // Verify tag itself still exists
        let tagCount = try db.scalarInt("SELECT count(*) FROM tags WHERE id = ?;", [.int(tagId)])
        XCTAssertEqual(tagCount, 1)
    }
}
