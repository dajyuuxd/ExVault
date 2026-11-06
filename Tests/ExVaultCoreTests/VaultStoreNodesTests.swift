// Unit tests for VaultStore: node hierarchy, sorting, trash, nested trash, restore, and purge.

import XCTest
@testable import ExVaultCore

final class VaultStoreNodesTests: XCTestCase {
    private var tempDbPath: String = ""
    private var db: Database?
    private var store: VaultStore?

    override func setUp() {
        super.setUp()
        tempDbPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("vault_nodes_\(UUID().uuidString).db")
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

    func testThreeLevelHierarchyAndBreadcrumb() throws {
        guard let store = store else { return }

        let level1 = try store.createFolder(parentId: nil, name: "Level1")
        let level2 = try store.createFolder(parentId: level1.id, name: "Level2")
        let file = try store.createFile(
            parentId: level2.id,
            name: "test.txt",
            size: 100,
            storedSize: 100,
            mime: "text/plain",
            codec: 0,
            crc32: 0x1234,
            blobId: "b001",
            mtime: nil
        )

        let crumbs = try store.breadcrumb(of: file.id)
        XCTAssertEqual(crumbs.count, 3)
        XCTAssertEqual(crumbs[0].id, level1.id)
        XCTAssertEqual(crumbs[0].name, "Level1")
        XCTAssertEqual(crumbs[1].id, level2.id)
        XCTAssertEqual(crumbs[1].name, "Level2")
        XCTAssertEqual(crumbs[2].id, file.id)
        XCTAssertEqual(crumbs[2].name, "test.txt")

        let emptyCrumbs = try store.breadcrumb(of: nil)
        XCTAssertTrue(emptyCrumbs.isEmpty)
    }

    func testSortingWithFoldersAlwaysFirst() throws {
        guard let store = store else { return }

        _ = try store.createFolder(parentId: nil, name: "b_folder")
        _ = try store.createFolder(parentId: nil, name: "a_folder")
        _ = try store.createFile(parentId: nil, name: "z_file.txt", size: 500, storedSize: 500, mime: "text/plain", codec: 0, crc32: 1, blobId: "b1", mtime: 1000)
        _ = try store.createFile(parentId: nil, name: "a_file.pdf", size: 100, storedSize: 100, mime: "application/pdf", codec: 0, crc32: 2, blobId: "b2", mtime: 2000)

        // 1. Sort by name asc
        let byNameAsc = try store.listChildren(parentId: nil, sort: .name, order: .asc)
        XCTAssertEqual(byNameAsc.map { $0.name }, ["a_folder", "b_folder", "a_file.pdf", "z_file.txt"])

        // 2. Sort by name desc
        let byNameDesc = try store.listChildren(parentId: nil, sort: .name, order: .desc)
        XCTAssertEqual(byNameDesc.map { $0.name }, ["b_folder", "a_folder", "z_file.txt", "a_file.pdf"])

        // 3. Sort by size asc (folders have size 0)
        let bySizeAsc = try store.listChildren(parentId: nil, sort: .size, order: .asc)
        XCTAssertEqual(bySizeAsc[0].kind, "folder")
        XCTAssertEqual(bySizeAsc[1].kind, "folder")
        XCTAssertEqual(bySizeAsc[2].name, "a_file.pdf")
        XCTAssertEqual(bySizeAsc[3].name, "z_file.txt")

        // 4. Sort by date asc
        let byDateAsc = try store.listChildren(parentId: nil, sort: .date, order: .asc)
        XCTAssertEqual(byDateAsc[0].kind, "folder")
        XCTAssertEqual(byDateAsc[1].kind, "folder")
        XCTAssertEqual(byDateAsc[2].name, "z_file.txt")
        XCTAssertEqual(byDateAsc[3].name, "a_file.pdf")

        // 5. Sort by type asc (ext .pdf before .txt)
        let byTypeAsc = try store.listChildren(parentId: nil, sort: .type, order: .asc)
        XCTAssertEqual(byTypeAsc[0].kind, "folder")
        XCTAssertEqual(byTypeAsc[1].kind, "folder")
        XCTAssertEqual(byTypeAsc[2].name, "a_file.pdf")
        XCTAssertEqual(byTypeAsc[3].name, "z_file.txt")
    }

    func testAutoUniqueNameOnCollision() throws {
        guard let store = store else { return }

        let f1 = try store.createFolder(parentId: nil, name: "docs")
        let f2 = try store.createFolder(parentId: nil, name: "docs")
        let f3 = try store.createFolder(parentId: nil, name: "docs")

        XCTAssertEqual(f1.name, "docs")
        XCTAssertEqual(f2.name, "docs (1)")
        XCTAssertEqual(f3.name, "docs (2)")

        let file1 = try store.createFile(parentId: nil, name: "photo.jpg", size: 10, storedSize: 10, mime: "image/jpeg", codec: 0, crc32: 0, blobId: "b1", mtime: nil)
        let file2 = try store.createFile(parentId: nil, name: "photo.jpg", size: 10, storedSize: 10, mime: "image/jpeg", codec: 0, crc32: 0, blobId: "b2", mtime: nil)

        XCTAssertEqual(file1.name, "photo.jpg")
        XCTAssertEqual(file2.name, "photo (1).jpg")
    }

    func testRenameConflictAndCaseChange() throws {
        guard let store = store else { return }

        let f1 = try store.createFolder(parentId: nil, name: "First")
        _ = try store.createFolder(parentId: nil, name: "Second")

        // Conflict rename
        do {
            _ = try store.rename(f1.id, to: "second")
            XCTFail("Should fail with name_conflict")
        } catch let err as StoreError {
            XCTAssertEqual(err.code, "name_conflict")
        }

        // Case change on same node is allowed
        let renamed = try store.rename(f1.id, to: "FIRST")
        XCTAssertEqual(renamed.name, "FIRST")
    }

    func testMoveValidationAndPreventionOfCycles() throws {
        guard let store = store else { return }

        let parent = try store.createFolder(parentId: nil, name: "Parent")
        let child = try store.createFolder(parentId: parent.id, name: "Child")
        let subChild = try store.createFolder(parentId: child.id, name: "SubChild")

        // Move into self
        do {
            _ = try store.move([parent.id], to: parent.id)
            XCTFail("Should fail invalid_move")
        } catch let err as StoreError {
            XCTAssertEqual(err.code, "invalid_move")
        }

        // Move into descendant
        do {
            _ = try store.move([parent.id], to: subChild.id)
            XCTFail("Should fail invalid_move")
        } catch let err as StoreError {
            XCTAssertEqual(err.code, "invalid_move")
        }

        // Valid move to root
        let moved = try store.move([child.id], to: nil)
        XCTAssertEqual(moved.count, 1)
        XCTAssertNil(moved[0].parentId)
    }

    func testTrashAndRestore() throws {
        guard let store = store else { return }

        let folder = try store.createFolder(parentId: nil, name: "Project")
        let file = try store.createFile(parentId: folder.id, name: "code.swift", size: 50, storedSize: 50, mime: "text/plain", codec: 0, crc32: 0, blobId: "b", mtime: nil)

        // Trash folder
        let count = try store.trash([folder.id])
        XCTAssertEqual(count, 1)

        // Children should no longer appear in active listing
        let activeRoot = try store.listChildren(parentId: nil, sort: .name, order: .asc)
        XCTAssertTrue(activeRoot.isEmpty)

        // Trash listing shows root of trash
        let trashed = try store.listTrash()
        XCTAssertEqual(trashed.count, 1)
        XCTAssertEqual(trashed[0].id, folder.id)

        // Child node also marked trashed
        let childNode = try store.getNode(file.id)
        XCTAssertNotNil(childNode?.trashedAt)

        // Restore folder
        let restoredCount = try store.restore([folder.id])
        XCTAssertEqual(restoredCount, 1)

        let activeAfter = try store.listChildren(parentId: nil, sort: .name, order: .asc)
        XCTAssertEqual(activeAfter.count, 1)
        XCTAssertEqual(activeAfter[0].id, folder.id)

        let childAfter = try store.getNode(file.id)
        XCTAssertNil(childAfter?.trashedAt)
    }

    func testNestedTrashBehavior() throws {
        guard let store = store else { return }

        let folder = try store.createFolder(parentId: nil, name: "Work")
        let file1 = try store.createFile(parentId: folder.id, name: "draft.txt", size: 10, storedSize: 10, mime: "text/plain", codec: 0, crc32: 0, blobId: "b1", mtime: nil)
        let file2 = try store.createFile(parentId: folder.id, name: "final.txt", size: 10, storedSize: 10, mime: "text/plain", codec: 0, crc32: 0, blobId: "b2", mtime: nil)

        // 1. Delete file1 directly
        _ = try store.trash([file1.id])

        // 2. Later delete the parent folder
        _ = try store.trash([folder.id])

        // 3. Restore parent folder
        _ = try store.restore([folder.id])

        // Folder is restored, file2 is alive, but file1 was trashed separately so it must remain trashed!
        let restoredFolderChildren = try store.listChildren(parentId: folder.id, sort: .name, order: .asc)
        XCTAssertEqual(restoredFolderChildren.count, 1)
        XCTAssertEqual(restoredFolderChildren[0].id, file2.id)

        let trashedFile1 = try store.getNode(file1.id)
        XCTAssertNotNil(trashedFile1?.trashedAt)
    }

    func testPurgeAndEmptyTrash() throws {
        guard let store = store, let db = db else { return }

        let folder = try store.createFolder(parentId: nil, name: "ToDelete")
        _ = try store.createFile(parentId: folder.id, name: "f1.txt", size: 10, storedSize: 10, mime: "text/plain", codec: 0, crc32: 0, blobId: "blob_purge_1", mtime: nil)
        _ = try store.createFile(parentId: folder.id, name: "f2.txt", size: 20, storedSize: 20, mime: "text/plain", codec: 0, crc32: 0, blobId: "blob_purge_2", mtime: nil)

        _ = try store.trash([folder.id])

        let purgeResult = try store.purge([folder.id])
        XCTAssertEqual(purgeResult.count, 1)
        XCTAssertEqual(Set(purgeResult.blobIds), Set(["blob_purge_1", "blob_purge_2"]))

        // Verify no orphan nodes left in DB
        let remaining = try db.scalarInt("SELECT count(*) FROM nodes;")
        XCTAssertEqual(remaining, 0)

        // Test emptyTrash on newly trashed items
        let fNew = try store.createFolder(parentId: nil, name: "NewTrash")
        _ = try store.trash([fNew.id])
        let emptyResult = try store.emptyTrash()
        XCTAssertEqual(emptyResult.count, 1)

        let totalAfter = try db.scalarInt("SELECT count(*) FROM nodes;")
        XCTAssertEqual(totalAfter, 0)
    }

    func testLargeListingPerformance() throws {
        guard let store = store else { return }

        let folder = try store.createFolder(parentId: nil, name: "Perf")
        let count = 500
        for i in 1...count {
            _ = try store.createFile(
                parentId: folder.id,
                name: "file_\(i).txt",
                size: Int64(i),
                storedSize: Int64(i),
                mime: "text/plain",
                codec: 0,
                crc32: UInt32(i),
                blobId: "b_\(i)",
                mtime: nil
            )
        }

        let start = Date()
        let items = try store.listChildren(parentId: folder.id, sort: .name, order: .asc)
        let elapsedMs = Date().timeIntervalSince(start) * 1000
        XCTAssertEqual(items.count, count)
        print("listChildren with \(count) nodes took \(String(format: "%.2f", elapsedMs)) ms")
    }
}
