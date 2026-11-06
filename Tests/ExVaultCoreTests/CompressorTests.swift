// Unit tests for Compressor (streaming raw DEFLATE round-trip, sampleRatio, corrupted data handling) and BlobStore.

import XCTest
@testable import ExVaultCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

final class CompressorTests: XCTestCase {
    private var tempDir: URL = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUp() {
        super.setUp()
        tempDir = URL(fileURLWithPath: (NSTemporaryDirectory() as NSString).appendingPathComponent("comp_test_\(UUID().uuidString)"))
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func createTempFile(data: Data) throws -> (path: String, fd: Int32) {
        let path = tempDir.appendingPathComponent("file_\(UUID().uuidString).bin").path
        let fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0o644)
        if fd < 0 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        if !data.isEmpty {
            try data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                try Net.writeFully(fd: fd, base, count: raw.count)
            }
        }
        lseek(fd, 0, SEEK_SET)
        return (path, fd)
    }

    private func roundTrip(data: Data) throws -> Data {
        let (_, inFD) = try createTempFile(data: data)
        defer { close(inFD) }

        var compressedData = Data()
        _ = try Compressor.compress(from: inFD, limitInput: nil) { chunk in
            compressedData.append(contentsOf: chunk)
        }

        let (_, compFD) = try createTempFile(data: compressedData)
        defer { close(compFD) }

        var decompressedData = Data()
        try Compressor.decompress(from: compFD) { chunk in
            decompressedData.append(contentsOf: chunk)
        }

        return decompressedData
    }

    func testRoundTripBoundarySizes() throws {
        let testSizes = [0, 1, 1023, 65535, 65536, 65537, 256 * 1024]
        for size in testSizes {
            // Fill with repeating pattern
            var bytes = [UInt8](repeating: 0, count: size)
            for i in 0..<size {
                bytes[i] = UInt8(i & 0xFF)
            }
            let original = Data(bytes)
            let result = try roundTrip(data: original)
            XCTAssertEqual(result.count, original.count, "Failed for size \(size)")
            XCTAssertEqual(Crc32.of(result), Crc32.of(original), "CRC mismatch for size \(size)")
        }
    }

    func testHighlyCompressibleDataRatio() throws {
        // 100 KB of repeated text
        let pattern = "ExVault LAN offline storage server for legacy iOS devices.\n"
        var text = ""
        while text.utf8.count < 100_000 {
            text.append(pattern)
        }
        guard let data = text.data(using: .utf8) else {
            XCTFail("Encoding failed")
            return
        }

        let (_, inFD) = try createTempFile(data: data)
        defer { close(inFD) }

        var compressed = Data()
        let result = try Compressor.compress(from: inFD, limitInput: nil) { chunk in
            compressed.append(contentsOf: chunk)
        }
        XCTAssertEqual(result.read, Int64(data.count))

        let ratio = Double(compressed.count) / Double(data.count)
        XCTAssertLessThan(ratio, 0.20, "Text compression ratio should be < 20%")

        // Decompress and verify
        let (_, compFD) = try createTempFile(data: compressed)
        defer { close(compFD) }
        var decompressed = Data()
        try Compressor.decompress(from: compFD) { chunk in
            decompressed.append(contentsOf: chunk)
        }
        XCTAssertEqual(decompressed, data)
    }

    func testRandomDataSampleRatio() throws {
        var rng = SystemRandomNumberGenerator()
        var randomBytes = [UInt8](repeating: 0, count: 64 * 1024)
        for i in 0..<randomBytes.count {
            randomBytes[i] = UInt8.random(in: 0...255, using: &rng)
        }
        let data = Data(randomBytes)

        let (_, fd) = try createTempFile(data: data)
        defer { close(fd) }

        let ratio = try Compressor.sampleRatio(fd: fd, sampleBytes: 32 * 1024)
        XCTAssertGreaterThan(ratio, 0.95, "Random data sample ratio should be > 0.95")
    }

    func testCorruptedCompressedDataDoesNotHang() throws {
        // Prepare valid compressed data
        let original = Data([UInt8](repeating: 0x41, count: 10_000))
        let (_, inFD) = try createTempFile(data: original)
        defer { close(inFD) }

        var compressed = Data()
        _ = try Compressor.compress(from: inFD, limitInput: nil) { chunk in
            compressed.append(contentsOf: chunk)
        }

        // Corrupt bytes in the middle of compressed stream
        if compressed.count > 10 {
            compressed[compressed.count / 2] ^= 0xFF
            compressed[compressed.count / 2 + 1] ^= 0xAA
        }

        let (_, compFD) = try createTempFile(data: compressed)
        defer { close(compFD) }

        // Must fail or complete without hanging
        do {
            try Compressor.decompress(from: compFD) { _ in }
        } catch {
            // Expected to throw CompressError.failed
            XCTAssertTrue(error is CompressError)
        }
    }

    func testBlobStorePathsAndManagement() throws {
        let store = try BlobStore(root: tempDir)

        // Shard path format blobs/<prefix>/<blobId>
        let blobPath = store.path(forBlob: "abcdef123456")
        XCTAssertTrue(blobPath.hasSuffix("blobs/ab/abcdef123456"))

        let thumbPath = store.thumbPath(forNode: "node123")
        XCTAssertTrue(thumbPath.hasSuffix("thumbs/node123.jpg"))

        let tmpPath = store.tmpPath(forUpload: "upload456")
        XCTAssertTrue(tmpPath.hasSuffix("tmp/upload456.part"))

        // Ensure shard dir
        try store.ensureShardDir(forBlob: "abcdef123456")
        let shardDir = (blobPath as NSString).deletingLastPathComponent
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: shardDir, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)

        // Non-existent deletes do not throw
        store.delete(blobId: "nonexistent")
        store.deleteThumb(nodeId: "nonexistent")

        // Free disk space query
        let free = store.diskFree()
        let total = store.diskTotal()
        XCTAssertGreaterThan(free, 0)
        XCTAssertGreaterThan(total, 0)
    }
}
