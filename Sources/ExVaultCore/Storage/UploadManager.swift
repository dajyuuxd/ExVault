// Chunked resumable upload manager with quota enforcement, background compression, and automatic cleanup.

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct UploadInfo: Codable, Equatable {
    public var id: String
    public var parentId: String?
    public var name: String
    public var size: Int64
    public var received: Int64
    public var mime: String
    public var state: String // "receiving" | "processing" | "done" | "error"
    public var nodeId: String?
    public var error: String?

    public init(
        id: String,
        parentId: String?,
        name: String,
        size: Int64,
        received: Int64,
        mime: String,
        state: String,
        nodeId: String?,
        error: String?
    ) {
        self.id = id
        self.parentId = parentId
        self.name = name
        self.size = size
        self.received = received
        self.mime = mime
        self.state = state
        self.nodeId = nodeId
        self.error = error
    }
}

public final class UploadManager {
    private let store: VaultStore
    private let blobs: BlobStore
    private let config: VaultConfig

    private let processQueue = DispatchQueue(label: "exv.process", qos: .utility)
    private let locksLock = NSLock()
    private var uploadLocks: [String: NSLock] = [:]

    public var onProcessed: ((String) -> Void)?

    public init(store: VaultStore, blobs: BlobStore, config: VaultConfig) {
        self.store = store
        self.blobs = blobs
        self.config = config
    }

    public func create(
        parentId: String?,
        name: String,
        size: Int64,
        mime: String,
        lastModified: Int64?,
        compress: Bool
    ) throws -> UploadInfo {
        guard let validName = NameRules.validate(name) else {
            throw StoreError(code: "invalid_name", message: "Invalid file name")
        }
        if size < 0 {
            throw StoreError(code: "bad_request", message: "Upload size cannot be negative")
        }
        guard try store.nodeExistsAliveFolder(parentId) else {
            throw StoreError(code: "not_found", message: "Parent folder not found")
        }

        // Quota check: size + receivingBytesTotal() + reserveFreeBytes <= diskFree()
        let diskFree = blobs.diskFree()
        let needed = size + receivingBytesTotal() + config.reserveFreeBytes
        if needed > diskFree {
            throw StoreError(code: "insufficient_storage", message: "Insufficient disk space")
        }

        let id = IDGen.newID()
        let partPath = blobs.tmpPath(forUpload: id)

        let fd = open(partPath, O_WRONLY | O_CREAT | O_EXCL, 0o644)
        if fd < 0 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        close(fd)

        let now = VaultStore.nowMs()
        let db = store.db

        try db.sync {
            try db.run(
                """
                INSERT INTO uploads (id, parent_id, name, size, received, crc, mime, mtime, compress, state, node_id, error, created_at, updated_at)
                VALUES (?, ?, ?, ?, 0, 0, ?, ?, ?, 'receiving', NULL, NULL, ?, ?);
                """,
                [
                    .text(id),
                    parentId.map { .text($0) } ?? .null,
                    .text(validName),
                    .int(size),
                    .text(mime),
                    lastModified.map { .int($0) } ?? .null,
                    .int(compress ? 1 : 0),
                    .int(now),
                    .int(now)
                ]
            )
        }

        return UploadInfo(
            id: id,
            parentId: parentId,
            name: validName,
            size: size,
            received: 0,
            mime: mime,
            state: "receiving",
            nodeId: nil,
            error: nil
        )
    }

    public func info(id: String) throws -> UploadInfo {
        let db = store.db
        return try db.sync {
            let sql = """
            SELECT id, parent_id, name, size, received, mime, state, node_id, error
            FROM uploads WHERE id = ?;
            """
            let rows = try db.query(sql, [.text(id)]) { row in
                UploadInfo(
                    id: row.text(0),
                    parentId: row.optText(1),
                    name: row.text(2),
                    size: row.int(3),
                    received: row.int(4),
                    mime: row.text(5),
                    state: row.text(6),
                    nodeId: row.optText(7),
                    error: row.optText(8)
                )
            }
            guard let item = rows.first else {
                throw StoreError(code: "not_found", message: "Upload not found")
            }
            return item
        }
    }

    public func appendChunk(
        id: String,
        offset: Int64,
        length: Int,
        reader: (UnsafeMutableRawPointer, Int) throws -> Int
    ) throws -> Int64 {
        let lock = lockForUpload(id)
        lock.lock()
        defer { lock.unlock() }

        let db = store.db
        let uploadRow = try db.sync { () -> (state: String, size: Int64, received: Int64, crc: UInt32)? in
            let rows = try db.query("SELECT state, size, received, crc FROM uploads WHERE id = ?;", [.text(id)]) { row in
                (state: row.text(0), size: row.int(1), received: row.int(2), crc: UInt32(row.int(3) & 0xFFFFFFFF))
            }
            return rows.first
        }

        guard let upload = uploadRow else {
            throw StoreError(code: "not_found", message: "Upload not found")
        }
        if upload.state != "receiving" {
            throw StoreError(code: "bad_request", message: "Upload is not in receiving state")
        }
        if offset != upload.received {
            throw StoreError(code: "offset_mismatch", message: "Chunk offset does not match received bytes", extra: ["offset": upload.received])
        }
        if upload.received + Int64(length) > upload.size {
            throw StoreError(code: "bad_request", message: "Chunk exceeds declared upload size")
        }

        let partPath = blobs.tmpPath(forUpload: id)
        let fd = open(partPath, O_WRONLY, 0o644)
        if fd < 0 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(fd) }

        if lseek(fd, off_t(offset), SEEK_SET) < 0 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        let bufSize = 64 * 1024
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buf.deallocate() }

        var writtenInChunk: Int64 = 0
        var runningCrc = upload.crc
        var readerError: Error? = nil

        while writtenInChunk < Int64(length) {
            let toRead = min(bufSize, Int(Int64(length) - writtenInChunk))
            do {
                let n = try reader(buf, toRead)
                if n == 0 { break }
                runningCrc = Crc32.update(runningCrc, UnsafeRawBufferPointer(start: buf, count: n))
                try Net.writeFully(fd: fd, buf, count: n)
                writtenInChunk += Int64(n)
            } catch {
                readerError = error
                break
            }
        }

        let newReceived = offset + writtenInChunk
        let now = VaultStore.nowMs()

        if let err = readerError {
            // Truncate to exact bytes successfully written so far
            ftruncate(fd, off_t(newReceived))
            try db.sync {
                try db.run(
                    "UPDATE uploads SET received = ?, crc = ?, updated_at = ? WHERE id = ?;",
                    [.int(newReceived), .int(Int64(runningCrc)), .int(now), .text(id)]
                )
            }
            throw err
        }

        try db.sync {
            try db.run(
                "UPDATE uploads SET received = ?, crc = ?, updated_at = ? WHERE id = ?;",
                [.int(newReceived), .int(Int64(runningCrc)), .int(now), .text(id)]
            )
        }

        return newReceived
    }

    public func finish(id: String) throws {
        let lock = lockForUpload(id)
        lock.lock()
        defer { lock.unlock() }

        let db = store.db
        let row = try db.sync { () -> (state: String, size: Int64, received: Int64)? in
            let rows = try db.query("SELECT state, size, received FROM uploads WHERE id = ?;", [.text(id)]) { row in
                (state: row.text(0), size: row.int(1), received: row.int(2))
            }
            return rows.first
        }

        guard let upload = row else {
            throw StoreError(code: "not_found", message: "Upload not found")
        }

        // Idempotent: if already processing or done, succeed without re-triggering
        if upload.state == "processing" || upload.state == "done" {
            return
        }

        if upload.received != upload.size {
            throw StoreError(code: "not_ready", message: "Upload chunking is incomplete")
        }

        let now = VaultStore.nowMs()
        try db.sync {
            try db.run("UPDATE uploads SET state = 'processing', updated_at = ? WHERE id = ?;", [.int(now), .text(id)])
        }

        processQueue.async { [weak self] in
            self?.process(id: id)
        }
    }

    public func cancel(id: String) throws {
        let lock = lockForUpload(id)
        lock.lock()
        defer {
            lock.unlock()
            removeLockForUpload(id)
        }

        let db = store.db
        let deleted = try db.sync {
            try db.run("DELETE FROM uploads WHERE id = ?;", [.text(id)])
        }
        if deleted == 0 {
            throw StoreError(code: "not_found", message: "Upload not found")
        }

        let partPath = blobs.tmpPath(forUpload: id)
        try? FileManager.default.removeItem(atPath: partPath)
    }

    public func cleanupAtStartup() {
        let db = store.db
        let now = VaultStore.nowMs()
        let expiryThreshold = now - (24 * 3600 * 1000) // 24 hours ago

        _ = try? db.sync {
            // Mark interrupted processing uploads as error
            try db.run("UPDATE uploads SET state = 'error', error = 'interrupted', updated_at = ? WHERE state = 'processing';", [.int(now)])

            // Find expired uploads in receiving state
            let expired = try db.query("SELECT id FROM uploads WHERE state = 'receiving' AND updated_at < ?;", [.int(expiryThreshold)]) {
                $0.text(0)
            }
            for expId in expired {
                let part = blobs.tmpPath(forUpload: expId)
                try? FileManager.default.removeItem(atPath: part)
                try? db.run("DELETE FROM uploads WHERE id = ?;", [.text(expId)])
            }
        }

        // Remove orphan .part files from tmp/
        let tmpDir = blobs.root.appendingPathComponent("tmp")
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: tmpDir.path) {
            for file in contents where file.hasSuffix(".part") {
                let uploadId = String(file.dropLast(".part".count))
                let hasRow = (try? db.sync {
                    try db.scalarInt("SELECT count(*) FROM uploads WHERE id = ?;", [.text(uploadId)]) ?? 0
                }) ?? 0
                if hasRow == 0 {
                    let path = tmpDir.appendingPathComponent(file).path
                    try? FileManager.default.removeItem(atPath: path)
                }
            }
        }
    }

    public func receivingBytesTotal() -> Int64 {
        let db = store.db
        return (try? db.sync {
            try db.scalarInt("SELECT COALESCE(SUM(size - received), 0) FROM uploads WHERE state = 'receiving';") ?? 0
        }) ?? 0
    }

    // MARK: - Background Processing Engine

    private func process(id: String) {
        let db = store.db
        struct Record {
            let parentId: String?
            let name: String
            let size: Int64
            let crc: UInt32
            let mime: String
            let mtime: Int64?
            let compress: Int
        }

        let record = try? db.sync { () -> Record? in
            let rows = try db.query("SELECT parent_id, name, size, crc, mime, mtime, compress FROM uploads WHERE id = ?;", [.text(id)]) { row in
                Record(
                    parentId: row.optText(0),
                    name: row.text(1),
                    size: row.int(2),
                    crc: UInt32(row.int(3) & 0xFFFFFFFF),
                    mime: row.text(4),
                    mtime: row.optInt(5),
                    compress: Int(row.int(6))
                )
            }
            return rows.first
        }

        guard let rec = record else {
            removeLockForUpload(id)
            onProcessed?(id)
            return
        }

        let partPath = blobs.tmpPath(forUpload: id)
        let blobId = IDGen.newID()
        let blobPath = blobs.path(forBlob: blobId)
        let tmpzPath = blobPath + ".tmpz"

        do {
            try blobs.ensureShardDir(forBlob: blobId)

            var codec = 0
            var storedSize = rec.size

            let decision: CompressionDecision
            if rec.compress == 0 || rec.size == 0 {
                decision = .never
            } else {
                decision = CompressionPolicy.decide(name: rec.name, size: rec.size)
            }

            switch decision {
            case .never:
                if rename(partPath, blobPath) != 0 {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                codec = 0
                storedSize = rec.size

            case .sample:
                let inFD = open(partPath, O_RDONLY, 0)
                if inFD < 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                let ratio = try Compressor.sampleRatio(fd: inFD, sampleBytes: 256 * 1024)
                close(inFD)

                if ratio > 0.85 {
                    if rename(partPath, blobPath) != 0 {
                        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                    }
                    codec = 0
                    storedSize = rec.size
                } else {
                    codec = try performCompression(partPath: partPath, blobPath: blobPath, tmpzPath: tmpzPath, size: rec.size, storedSize: &storedSize)
                }

            case .always:
                codec = try performCompression(partPath: partPath, blobPath: blobPath, tmpzPath: tmpzPath, size: rec.size, storedSize: &storedSize)
            }

            let isGenericMime = rec.mime.isEmpty || rec.mime == "application/octet-stream" || rec.mime == "binary/octet-stream"
            let effectiveMime = isGenericMime ? MimeTypes.mime(forName: rec.name) : rec.mime
            let node = try store.createFile(
                parentId: rec.parentId,
                name: rec.name,
                size: rec.size,
                storedSize: storedSize,
                mime: effectiveMime,
                codec: codec,
                crc32: rec.crc,
                blobId: blobId,
                mtime: rec.mtime
            )

            let now = VaultStore.nowMs()
            try db.sync {
                try db.run(
                    "UPDATE uploads SET state = 'done', node_id = ?, error = NULL, updated_at = ? WHERE id = ?;",
                    [.text(node.id), .int(now), .text(id)]
                )
            }
        } catch {
            // On failure clean up any temporary blobs
            blobs.delete(blobId: blobId)
            try? FileManager.default.removeItem(atPath: tmpzPath)
            try? FileManager.default.removeItem(atPath: partPath)

            let now = VaultStore.nowMs()
            _ = try? db.sync {
                try db.run(
                    "UPDATE uploads SET state = 'error', error = ?, updated_at = ? WHERE id = ?;",
                    [.text("\(error)"), .int(now), .text(id)]
                )
            }
        }

        removeLockForUpload(id)
        onProcessed?(id)
    }

    private func performCompression(
        partPath: String,
        blobPath: String,
        tmpzPath: String,
        size: Int64,
        storedSize: inout Int64
    ) throws -> Int {
        let inFD = open(partPath, O_RDONLY, 0)
        if inFD < 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(inFD) }

        let outFD = open(tmpzPath, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        if outFD < 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(outFD) }

        let compResult = try Compressor.compressFile(from: inFD, to: outFD)

        if compResult.written > Int64(Double(size) * 0.95) {
            // Compressed output is not significantly smaller: preserve raw
            try? FileManager.default.removeItem(atPath: tmpzPath)
            if rename(partPath, blobPath) != 0 {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            storedSize = size
            return 0 // raw
        } else {
            if rename(tmpzPath, blobPath) != 0 {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            try? FileManager.default.removeItem(atPath: partPath)
            storedSize = compResult.written
            return 1 // zlib
        }
    }

    private func lockForUpload(_ id: String) -> NSLock {
        locksLock.lock()
        defer { locksLock.unlock() }
        if let existing = uploadLocks[id] {
            return existing
        }
        let lock = NSLock()
        uploadLocks[id] = lock
        return lock
    }

    private func removeLockForUpload(_ id: String) {
        locksLock.lock()
        defer { locksLock.unlock() }
        uploadLocks.removeValue(forKey: id)
    }
}
