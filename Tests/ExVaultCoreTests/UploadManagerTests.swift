// Unit tests for UploadManager: chunked upload, CRC verification, auto-compression, quota, and cleanup.

import XCTest
@testable import ExVaultCore

final class UploadManagerTests: XCTestCase {
    private var tempDir: URL = URL(fileURLWithPath: NSTemporaryDirectory())
    private var db: Database?
    private var store: VaultStore?
    private var blobs: BlobStore?
    private var config: VaultConfig?
    private var uploadManager: UploadManager?

    override func setUp() {
        super.setUp()
        tempDir = URL(fileURLWithPath: (NSTemporaryDirectory() as NSString).appendingPathComponent("up_test_\(UUID().uuidString)"))
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)

        do {
            let database = try Database(path: tempDir.appendingPathComponent("vault.db").path)
            self.db = database
            let vStore = VaultStore(db: database)
            self.store = vStore
            let bStore = try BlobStore(root: tempDir)
            self.blobs = bStore
            let cfg = VaultConfig(dataDir: tempDir, webRoot: tempDir, reserveFreeBytes: 10 * 1024 * 1024)
            self.config = cfg
            self.uploadManager = UploadManager(store: vStore, blobs: bStore, config: cfg)
        } catch {
            XCTFail("Failed to initialize upload manager test dependencies: \(error)")
        }
    }

    override func tearDown() {
        uploadManager = nil
        blobs = nil
        store = nil
        db = nil
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testUploadTextChunkedAndDecompressCheck() throws {
        guard let manager = uploadManager, let store = store, let blobs = blobs else { return }

        // Repeating text of 300 KB
        let chunkCount = 3
        let chunkSize = 100_000
        let totalSize = Int64(chunkCount * chunkSize)
        let sample = "ExVault chunked upload testing line with plenty of repetitive content.\n"
        var text = ""
        while text.utf8.count < chunkSize {
            text.append(sample)
        }
        let chunkData = Data(text.utf8.prefix(chunkSize))
        var fullData = Data()
        for _ in 0..<chunkCount {
            fullData.append(chunkData)
        }
        let expectedCrc = Crc32.of(fullData)

        let exp = expectation(description: "Upload processed")
        manager.onProcessed = { _ in
            exp.fulfill()
        }

        let upload = try manager.create(
            parentId: nil,
            name: "document.txt",
            size: totalSize,
            mime: "text/plain",
            lastModified: 1000,
            compress: true
        )

        for i in 0..<chunkCount {
            let offset = Int64(i * chunkSize)
            let received = try manager.appendChunk(id: upload.id, offset: offset, length: chunkSize) { buf, maxCount in
                let toCopy = min(maxCount, chunkSize)
                chunkData.withUnsafeBytes { raw in
                    guard let base = raw.baseAddress else { return }
                    buf.copyMemory(from: base, byteCount: toCopy)
                }
                return toCopy
            }
            XCTAssertEqual(received, offset + Int64(chunkSize))
        }

        try manager.finish(id: upload.id)
        wait(for: [exp], timeout: 5.0)

        let info = try manager.info(id: upload.id)
        XCTAssertEqual(info.state, "done")
        guard let nodeId = info.nodeId else {
            XCTFail("Node ID missing")
            return
        }

        let node = try store.getNode(nodeId)
        XCTAssertEqual(node?.codec, "zlib")
        guard let storedSize = node?.storedSize, let size = node?.size else {
            XCTFail("Node missing sizes")
            return
        }
        XCTAssertLessThan(storedSize, size)

        // Decompress blob to verify integrity
        guard let blobInfo = try store.fileBlobInfo(nodeId) else {
            XCTFail("Blob info missing")
            return
        }
        let blobPath = blobs.path(forBlob: blobInfo.blobId)
        let fd = open(blobPath, O_RDONLY, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }

        var decompressed = Data()
        try Compressor.decompress(from: fd) { chunk in
            decompressed.append(contentsOf: chunk)
        }
        XCTAssertEqual(decompressed.count, Int(totalSize))
        XCTAssertEqual(Crc32.of(decompressed), expectedCrc)
    }

    func testUploadJpegKeptRaw() throws {
        guard let manager = uploadManager, let store = store else { return }

        let size: Int64 = 500_000
        var rng = SystemRandomNumberGenerator()
        var bytes = [UInt8](repeating: 0, count: Int(size))
        for i in 0..<bytes.count {
            bytes[i] = UInt8.random(in: 0...255, using: &rng)
        }
        let data = Data(bytes)

        let exp = expectation(description: "Upload processed")
        manager.onProcessed = { _ in exp.fulfill() }

        let upload = try manager.create(
            parentId: nil,
            name: "photo.jpg",
            size: size,
            mime: "image/jpeg",
            lastModified: nil,
            compress: true
        )

        _ = try manager.appendChunk(id: upload.id, offset: 0, length: Int(size)) { buf, maxCount in
            data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                buf.copyMemory(from: base, byteCount: Int(size))
            }
            return Int(size)
        }

        try manager.finish(id: upload.id)
        wait(for: [exp], timeout: 5.0)

        let info = try manager.info(id: upload.id)
        XCTAssertEqual(info.state, "done")
        let node = try store.getNode(info.nodeId ?? "")
        XCTAssertEqual(node?.codec, "raw")
        XCTAssertEqual(node?.storedSize, size)
    }

    func testUploadBinSampleRatioDecisions() throws {
        guard let manager = uploadManager, let store = store else { return }

        // 1. Random .bin -> sample ratio > 0.85 -> raw
        let size: Int64 = 100_000
        var rng = SystemRandomNumberGenerator()
        var randBytes = [UInt8](repeating: 0, count: Int(size))
        for i in 0..<randBytes.count {
            randBytes[i] = UInt8.random(in: 0...255, using: &rng)
        }
        let randData = Data(randBytes)

        let exp1 = expectation(description: "Random bin processed")
        manager.onProcessed = { _ in exp1.fulfill() }

        let up1 = try manager.create(parentId: nil, name: "random.bin", size: size, mime: "", lastModified: nil, compress: true)
        _ = try manager.appendChunk(id: up1.id, offset: 0, length: Int(size)) { buf, _ in
            randData.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                buf.copyMemory(from: base, byteCount: Int(size))
            }
            return Int(size)
        }
        try manager.finish(id: up1.id)
        wait(for: [exp1], timeout: 5.0)

        let info1 = try manager.info(id: up1.id)
        let node1 = try store.getNode(info1.nodeId ?? "")
        XCTAssertEqual(node1?.codec, "raw")

        // 2. Zero-filled .bin -> sample ratio < 0.85 -> zlib
        let zeroData = Data([UInt8](repeating: 0, count: Int(size)))
        let exp2 = expectation(description: "Zero bin processed")
        manager.onProcessed = { _ in exp2.fulfill() }

        let up2 = try manager.create(parentId: nil, name: "zeros.bin", size: size, mime: "", lastModified: nil, compress: true)
        _ = try manager.appendChunk(id: up2.id, offset: 0, length: Int(size)) { buf, _ in
            zeroData.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                buf.copyMemory(from: base, byteCount: Int(size))
            }
            return Int(size)
        }
        try manager.finish(id: up2.id)
        wait(for: [exp2], timeout: 5.0)

        let info2 = try manager.info(id: up2.id)
        let node2 = try store.getNode(info2.nodeId ?? "")
        XCTAssertEqual(node2?.codec, "zlib")
    }

    func testZeroByteFileUpload() throws {
        guard let manager = uploadManager, let store = store else { return }

        let exp = expectation(description: "Zero byte upload processed")
        manager.onProcessed = { _ in exp.fulfill() }

        let upload = try manager.create(parentId: nil, name: "empty.txt", size: 0, mime: "text/plain", lastModified: nil, compress: true)
        try manager.finish(id: upload.id)
        wait(for: [exp], timeout: 5.0)

        let info = try manager.info(id: upload.id)
        XCTAssertEqual(info.state, "done")
        let node = try store.getNode(info.nodeId ?? "")
        XCTAssertEqual(node?.size, 0)
        XCTAssertEqual(node?.storedSize, 0)
        XCTAssertEqual(node?.codec, "raw")
    }

    func testOffsetMismatchAndResume() throws {
        guard let manager = uploadManager else { return }

        let upload = try manager.create(parentId: nil, name: "file.txt", size: 1000, mime: "", lastModified: nil, compress: true)

        // Send wrong offset 50
        do {
            _ = try manager.appendChunk(id: upload.id, offset: 50, length: 100) { _, _ in 100 }
            XCTFail("Should fail with offset_mismatch")
        } catch let err as StoreError {
            XCTAssertEqual(err.code, "offset_mismatch")
            XCTAssertEqual(err.extra["offset"], 0)
        }

        // Send correct offset 0
        let received = try manager.appendChunk(id: upload.id, offset: 0, length: 100) { _, _ in 100 }
        XCTAssertEqual(received, 100)
    }

    func testReaderErrorMidwayAndTruncation() throws {
        guard let manager = uploadManager, let blobs = blobs else { return }

        let upload = try manager.create(parentId: nil, name: "test.txt", size: 10_000, mime: "", lastModified: nil, compress: true)

        enum SimulatedReaderError: Error {
            case networkDrop
        }

        var calls = 0
        do {
            _ = try manager.appendChunk(id: upload.id, offset: 0, length: 1000) { buf, _ in
                calls += 1
                if calls == 1 {
                    return 500
                } else {
                    throw SimulatedReaderError.networkDrop
                }
            }
            XCTFail("Should throw reader error")
        } catch SimulatedReaderError.networkDrop {
            // Expected
        }

        // Received should be 500
        let info = try manager.info(id: upload.id)
        XCTAssertEqual(info.received, 500)

        // Part file on disk should be exactly 500 bytes
        let partPath = blobs.tmpPath(forUpload: upload.id)
        let sizeOnDisk = blobs.fileSize(atPath: partPath)
        XCTAssertEqual(sizeOnDisk, 500)
    }

    func testCancelAndFinishNotReady() throws {
        guard let manager = uploadManager, let blobs = blobs else { return }

        let upload = try manager.create(parentId: nil, name: "cancel.txt", size: 5000, mime: "", lastModified: nil, compress: true)

        // Finish before receiving all bytes -> not_ready
        do {
            try manager.finish(id: upload.id)
            XCTFail("Should fail with not_ready")
        } catch let err as StoreError {
            XCTAssertEqual(err.code, "not_ready")
        }

        // Cancel
        try manager.cancel(id: upload.id)
        let partPath = blobs.tmpPath(forUpload: upload.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partPath))

        do {
            _ = try manager.info(id: upload.id)
            XCTFail("Should throw not_found after cancel")
        } catch let err as StoreError {
            XCTAssertEqual(err.code, "not_found")
        }
    }

    func testNameCollisionAndParentTrashedDuringUpload() throws {
        guard let manager = uploadManager, let store = store else { return }

        // 1. Name collision auto unique
        let exp1 = expectation(description: "Upload 1")
        manager.onProcessed = { _ in exp1.fulfill() }
        let up1 = try manager.create(parentId: nil, name: "file.txt", size: 0, mime: "", lastModified: nil, compress: false)
        try manager.finish(id: up1.id)
        wait(for: [exp1], timeout: 5.0)

        let exp2 = expectation(description: "Upload 2")
        manager.onProcessed = { _ in exp2.fulfill() }
        let up2 = try manager.create(parentId: nil, name: "file.txt", size: 0, mime: "", lastModified: nil, compress: false)
        try manager.finish(id: up2.id)
        wait(for: [exp2], timeout: 5.0)

        let node1 = try store.getNode(try manager.info(id: up1.id).nodeId ?? "")
        let node2 = try store.getNode(try manager.info(id: up2.id).nodeId ?? "")
        XCTAssertEqual(node1?.name, "file.txt")
        XCTAssertEqual(node2?.name, "file (1).txt")

        // 2. Parent trashed during upload -> fallback to root
        let folder = try store.createFolder(parentId: nil, name: "UploadFolder")
        let up3 = try manager.create(parentId: folder.id, name: "file3.txt", size: 0, mime: "", lastModified: nil, compress: false)

        _ = try store.trash([folder.id])

        let exp3 = expectation(description: "Upload 3")
        manager.onProcessed = { _ in exp3.fulfill() }
        try manager.finish(id: up3.id)
        wait(for: [exp3], timeout: 5.0)

        let node3 = try store.getNode(try manager.info(id: up3.id).nodeId ?? "")
        XCTAssertNil(node3?.parentId, "Node should have fallen back to root")
    }

    func testCompressOffWithTextFile() throws {
        guard let manager = uploadManager, let store = store else { return }

        let exp = expectation(description: "Compress off upload")
        manager.onProcessed = { _ in exp.fulfill() }

        let upload = try manager.create(parentId: nil, name: "raw_text.txt", size: 10, mime: "text/plain", lastModified: nil, compress: false)
        _ = try manager.appendChunk(id: upload.id, offset: 0, length: 10) { buf, _ in
            buf.initializeMemory(as: UInt8.self, repeating: 0x41, count: 10)
            return 10
        }
        try manager.finish(id: upload.id)
        wait(for: [exp], timeout: 5.0)

        let info = try manager.info(id: upload.id)
        let node = try store.getNode(info.nodeId ?? "")
        XCTAssertEqual(node?.codec, "raw")
        XCTAssertEqual(node?.storedSize, 10)
    }

    func testQuotaInsufficientStorage() throws {
        guard let manager = uploadManager, let blobs = blobs else { return }

        // Mock diskFreeProvider to return 5MB (less than reserve 10MB)
        blobs.diskFreeProvider = { 5 * 1024 * 1024 }

        do {
            _ = try manager.create(parentId: nil, name: "large.bin", size: 1000, mime: "", lastModified: nil, compress: true)
            XCTFail("Should fail with insufficient_storage")
        } catch let err as StoreError {
            XCTAssertEqual(err.code, "insufficient_storage")
        }
    }

    func testCleanupAtStartup() throws {
        guard let manager = uploadManager, let blobs = blobs, let db = db else { return }

        let now = VaultStore.nowMs()
        // 1. Insert upload with state 'processing'
        try db.run(
            """
            INSERT INTO uploads (id, parent_id, name, size, received, crc, mime, mtime, compress, state, created_at, updated_at)
            VALUES ('interrupted_up', NULL, 'interrupted.txt', 100, 100, 0, '', NULL, 0, 'processing', ?, ?);
            """,
            [.int(now), .int(now)]
        )

        // 2. Create orphan .part file in tmp/ without DB row
        let orphanPath = blobs.tmpPath(forUpload: "orphan_upload")
        try Data([1, 2, 3]).write(to: URL(fileURLWithPath: orphanPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: orphanPath))

        // Run cleanup
        manager.cleanupAtStartup()

        // Verify interrupted upload changed to error
        let info = try manager.info(id: "interrupted_up")
        XCTAssertEqual(info.state, "error")
        XCTAssertEqual(info.error, "interrupted")

        // Verify orphan .part file was removed
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanPath))
    }
}
