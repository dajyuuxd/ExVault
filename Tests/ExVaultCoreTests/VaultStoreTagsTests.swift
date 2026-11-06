// Unit tests for VaultStore: tags CRUD, search indexing with escape characters, and vault statistics.

import XCTest
@testable import ExVaultCore

final class VaultStoreTagsTests: XCTestCase {
    private var tempDbPath: String = ""
    private var db: Database?
    private var store: VaultStore?

    override func setUp() {
        super.setUp()
        tempDbPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("vault_tags_\(UUID().uuidString).db")
        do {
            let database = try Database(path: tempDbPath)
            self.db = database
            self.store = VaultStore(db: database)
        } catch {
            XCTFail("Failed to initialize test database: \(error)")
        }
    }

    override func tearDown() {
        db = nil
        store = nil
        if !tempDbPath.isEmpty && FileManager.default.fileExists(atPath: tempDbPath) {
            try? FileManager.default.removeItem(atPath: tempDbPath)
            try? FileManager.default.removeItem(atPath: tempDbPath + "-wal")
            try? FileManager.default.removeItem(atPath: tempDbPath + "-shm")
        }
        super.tearDown()
    }

    func testTagCRUDAndCaseInsensitiveCollision() throws {
        guard let store = store else { return }

        // 1. Create tag
        let tag1 = try store.createTag(name: "Important", color: "#ff0000")
        XCTAssertEqual(tag1.name, "Important")
        XCTAssertEqual(tag1.color, "#ff0000")

        // 2. Case-insensitive collision on creation
        do {
            _ = try store.createTag(name: "important", color: "#00ff00")
            XCTFail("Should fail with name_conflict")
        } catch let err as StoreError {
            XCTAssertEqual(err.code, "name_conflict")
        }

        // 3. Invalid tag name
        do {
            _ = try store.createTag(name: "   ", color: "#000000")
            XCTFail("Should fail with invalid_name")
        } catch let err as StoreError {
            XCTAssertEqual(err.code, "invalid_name")
        }

        // 4. Invalid tag color
        do {
            _ = try store.createTag(name: "Work", color: "invalid_color")
            XCTFail("Should fail with bad_request")
        } catch let err as StoreError {
            XCTAssertEqual(err.code, "bad_request")
        }

        // 5. Update tag
        let tag2 = try store.createTag(name: "Personal", color: nil)
        XCTAssertEqual(tag2.color, "#888888")

        let updated = try store.updateTag(id: tag2.id, name: "Family", color: "#112233")
        XCTAssertEqual(updated.name, "Family")
        XCTAssertEqual(updated.color, "#112233")

        // 6. List tags (sorted by name)
        let allTags = try store.listTags()
        XCTAssertEqual(allTags.count, 2)
        XCTAssertEqual(allTags.map { $0.name }, ["Family", "Important"])

        // 7. Delete tag
        try store.deleteTag(id: tag1.id)
        let remainingTags = try store.listTags()
        XCTAssertEqual(remainingTags.count, 1)
        XCTAssertEqual(remainingTags[0].name, "Family")
    }

    func testApplyAndRemoveTagsBulk() throws {
        guard let store = store else { return }

        let tag1 = try store.createTag(name: "T1", color: nil)
        let tag2 = try store.createTag(name: "T2", color: nil)

        let f1 = try store.createFile(parentId: nil, name: "file1.txt", size: 10, storedSize: 10, mime: "text/plain", codec: 0, crc32: 0, blobId: "b1", mtime: nil)
        let f2 = try store.createFile(parentId: nil, name: "file2.txt", size: 20, storedSize: 20, mime: "text/plain", codec: 0, crc32: 0, blobId: "b2", mtime: nil)

        // Apply tag1 and tag2 to both files
        let updated = try store.applyTags(ids: [f1.id, f2.id], add: [tag1.id, tag2.id], remove: [])
        XCTAssertEqual(updated.count, 2)
        XCTAssertEqual(Set(updated[0].tagIds), Set([tag1.id, tag2.id]))
        XCTAssertEqual(Set(updated[1].tagIds), Set([tag1.id, tag2.id]))

        // Remove tag1 from file1
        let updated2 = try store.applyTags(ids: [f1.id], add: [], remove: [tag1.id])
        XCTAssertEqual(updated2.count, 1)
        XCTAssertEqual(updated2[0].tagIds, [tag2.id])

        // Delete tag2: f1 had only tag2, so f1 has no tags left. f2 still has tag1.
        try store.deleteTag(id: tag2.id)
        let node1 = try store.getNode(f1.id)
        let node2 = try store.getNode(f2.id)
        XCTAssertEqual(node1?.tagIds, [])
        XCTAssertEqual(node2?.tagIds, [tag1.id])

        // Now delete tag1 as well, so f2 also has no tags left
        try store.deleteTag(id: tag1.id)
        let node2After = try store.getNode(f2.id)
        XCTAssertEqual(node2After?.tagIds, [])
    }

    func testSearchWithEscapingVietnameseAndTags() throws {
        guard let store = store else { return }

        let folder = try store.createFolder(parentId: nil, name: "Tài liệu")
        let specialFile1 = try store.createFile(parentId: folder.id, name: "100%_sale.txt", size: 10, storedSize: 10, mime: "text/plain", codec: 0, crc32: 0, blobId: "b1", mtime: nil)
        let specialFile2 = try store.createFile(parentId: folder.id, name: "1000_sale.txt", size: 10, storedSize: 10, mime: "text/plain", codec: 0, crc32: 0, blobId: "b2", mtime: nil)
        let viFile = try store.createFile(parentId: folder.id, name: "Ảnh kỷ niệm 2026.png", size: 100, storedSize: 100, mime: "image/png", codec: 0, crc32: 0, blobId: "b3", mtime: nil)

        let tag = try store.createTag(name: "Starred", color: nil)
        _ = try store.applyTags(ids: [specialFile1.id], add: [tag.id], remove: [])

        // 1. Search literal '%' - should only match '100%_sale.txt' and NOT '1000_sale.txt'
        let percentResults = try store.search(q: "%", tagId: nil)
        XCTAssertEqual(percentResults.count, 1)
        XCTAssertEqual(percentResults[0].node.name, "100%_sale.txt")
        XCTAssertEqual(percentResults[0].pathText, "/Tài liệu")

        // 2. Search literal '_'
        let underscoreResults = try store.search(q: "_sale", tagId: nil)
        XCTAssertEqual(underscoreResults.count, 2)

        // 3. Search Vietnamese diacritics
        let viResults = try store.search(q: "Ảnh kỷ niệm", tagId: nil)
        XCTAssertEqual(viResults.count, 1)
        XCTAssertEqual(viResults[0].node.id, viFile.id)

        // 4. Search by tag only
        let tagResults = try store.search(q: nil, tagId: tag.id)
        XCTAssertEqual(tagResults.count, 1)
        XCTAssertEqual(tagResults[0].node.id, specialFile1.id)

        // 5. Trashed nodes must not appear in search
        _ = try store.trash([specialFile1.id])
        let afterTrashResults = try store.search(q: "%", tagId: nil)
        XCTAssertTrue(afterTrashResults.isEmpty)
    }

    func testVaultStats() throws {
        guard let store = store else { return }

        let initial = try store.stats()
        XCTAssertEqual(initial.fileCount, 0)
        XCTAssertEqual(initial.folderCount, 0)
        XCTAssertEqual(initial.totalBytes, 0)
        XCTAssertEqual(initial.storedBytes, 0)
        XCTAssertEqual(initial.trashBytes, 0)

        let folder = try store.createFolder(parentId: nil, name: "Media")
        let f1 = try store.createFile(parentId: folder.id, name: "doc.txt", size: 1000, storedSize: 600, mime: "text/plain", codec: 1, crc32: 123, blobId: "b1", mtime: nil)
        let f2 = try store.createFile(parentId: folder.id, name: "photo.jpg", size: 2000, storedSize: 2000, mime: "image/jpeg", codec: 0, crc32: 456, blobId: "b2", mtime: nil)

        let afterAdd = try store.stats()
        XCTAssertEqual(afterAdd.folderCount, 1)
        XCTAssertEqual(afterAdd.fileCount, 2)
        XCTAssertEqual(afterAdd.totalBytes, 3000)
        XCTAssertEqual(afterAdd.storedBytes, 2600)
        XCTAssertEqual(afterAdd.trashBytes, 0)

        // Trash f1
        _ = try store.trash([f1.id])
        let afterTrash = try store.stats()
        XCTAssertEqual(afterTrash.fileCount, 1) // only f2 is active
        XCTAssertEqual(afterTrash.totalBytes, 2000)
        XCTAssertEqual(afterTrash.storedBytes, 2000)
        XCTAssertEqual(afterTrash.trashBytes, 600)

        // Restore f1
        _ = try store.restore([f1.id])
        let afterRestore = try store.stats()
        XCTAssertEqual(afterRestore.fileCount, 2)
        XCTAssertEqual(afterRestore.totalBytes, 3000)
        XCTAssertEqual(afterRestore.storedBytes, 2600)
        XCTAssertEqual(afterRestore.trashBytes, 0)
    }
}
