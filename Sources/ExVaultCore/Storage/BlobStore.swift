// Filesystem storage manager for content blobs, thumbnails, and chunked upload parts.

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public final class BlobStore {
    public let root: URL

    public init(root: URL) throws {
        self.root = root
        let fm = FileManager.default
        let blobsDir = root.appendingPathComponent("blobs")
        let thumbsDir = root.appendingPathComponent("thumbs")
        let tmpDir = root.appendingPathComponent("tmp")

        try fm.createDirectory(at: blobsDir, withIntermediateDirectories: true, attributes: nil)
        try fm.createDirectory(at: thumbsDir, withIntermediateDirectories: true, attributes: nil)
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true, attributes: nil)
    }

    public func path(forBlob id: String) -> String {
        let prefix = id.count >= 2 ? String(id.prefix(2)) : "00"
        return root
            .appendingPathComponent("blobs")
            .appendingPathComponent(prefix)
            .appendingPathComponent(id)
            .path
    }

    public func thumbPath(forNode id: String) -> String {
        return root
            .appendingPathComponent("thumbs")
            .appendingPathComponent("\(id).jpg")
            .path
    }

    public func tmpPath(forUpload id: String) -> String {
        return root
            .appendingPathComponent("tmp")
            .appendingPathComponent("\(id).part")
            .path
    }

    public func ensureShardDir(forBlob id: String) throws {
        let prefix = id.count >= 2 ? String(id.prefix(2)) : "00"
        let shardDir = root.appendingPathComponent("blobs").appendingPathComponent(prefix)
        try FileManager.default.createDirectory(at: shardDir, withIntermediateDirectories: true, attributes: nil)
    }

    public func delete(blobId: String) {
        let filePath = path(forBlob: blobId)
        try? FileManager.default.removeItem(atPath: filePath)
    }

    public func deleteThumb(nodeId: String) {
        let filePath = thumbPath(forNode: nodeId)
        try? FileManager.default.removeItem(atPath: filePath)
    }

    public func fileSize(atPath p: String) -> Int64? {
        var st = stat()
        if stat(p, &st) == 0 {
            return Int64(st.st_size)
        }
        return nil
    }

    public func diskFree() -> Int64 {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: root.path)
            if let free = attrs[.systemFreeSize] as? NSNumber {
                return free.int64Value
            }
        } catch {
            return 0
        }
        return 0
    }

    public func diskTotal() -> Int64 {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: root.path)
            if let total = attrs[.systemSize] as? NSNumber {
                return total.int64Value
            }
        } catch {
            return 0
        }
        return 0
    }
}
