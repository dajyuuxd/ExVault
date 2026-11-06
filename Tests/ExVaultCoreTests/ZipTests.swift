// Unit and integration tests for ZIP archive writer, entry generation, limits, and HTTP endpoint.

import XCTest
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
@testable import ExVaultCore

final class ZipTests: XCTestCase {

    private final class MemoryResponseWriter: ResponseWriter {
        var data = Data()
        func write(_ ptr: UnsafeRawPointer, count: Int) throws {
            data.append(ptr.assumingMemoryBound(to: UInt8.self), count: count)
        }
    }

    private var tempDir: String!
    private var server: VaultServer!
    private var port: Int = 0
    private var sessionToken: String = ""

    override func setUp() {
        super.setUp()
        tempDir = NSTemporaryDirectory() + "exvault_zip_test_" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if server != nil {
            server.stop()
            server = nil
        }
        if let dir = tempDir {
            try? FileManager.default.removeItem(atPath: dir)
        }
        super.tearDown()
    }

    // MARK: - 1. In-Memory ZIP Writer Format Validation

    func testZipWriterInMemoryAndFormatValidation() throws {
        let textData = Data("Xin chào Việt Nam! 123456789".utf8)
        let textCrc = Crc32.of(textData)
        let binData = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0xFF])
        let binCrc = Crc32.of(binData)

        let entries = [
            ZipEntry(path: "folder/", isDir: true, size: 0, crc32: 0),
            ZipEntry(path: "folder/tài liệu.txt", isDir: false, size: Int64(textData.count), crc32: textCrc),
            ZipEntry(path: "data.bin", isDir: false, size: Int64(binData.count), crc32: binCrc)
        ]

        let expectedLength = ZipWriter.totalLength(entries: entries)
        let memWriter = MemoryResponseWriter()
        let zipWriter = ZipWriter(entries: entries)

        try zipWriter.write(to: memWriter) { entry, sink in
            if entry.path == "folder/tài liệu.txt" {
                try textData.withUnsafeBytes { raw in
                    try sink(raw)
                }
            } else if entry.path == "data.bin" {
                try binData.withUnsafeBytes { raw in
                    try sink(raw)
                }
            }
        }

        let zipData = memWriter.data
        XCTAssertEqual(Int64(zipData.count), expectedLength)

        // Check Local File Header signature (0x04034B50 -> PK\x03\x04)
        XCTAssertEqual(zipData[0], 0x50)
        XCTAssertEqual(zipData[1], 0x4B)
        XCTAssertEqual(zipData[2], 0x03)
        XCTAssertEqual(zipData[3], 0x04)

        // Check End of Central Directory signature at the end (last 22 bytes: 0x06054B50 -> PK\x05\x06)
        let eocdOffset = zipData.count - 22
        XCTAssertEqual(zipData[eocdOffset], 0x50)
        XCTAssertEqual(zipData[eocdOffset + 1], 0x4B)
        XCTAssertEqual(zipData[eocdOffset + 2], 0x05)
        XCTAssertEqual(zipData[eocdOffset + 3], 0x06)

        // Check total entries in EOCD (offset 10 in EOCD is UInt16 entry count)
        let totalRecords = UInt16(zipData[eocdOffset + 10]) | (UInt16(zipData[eocdOffset + 11]) << 8)
        XCTAssertEqual(totalRecords, 3)

        // Read central directory offset from EOCD (offset 16 in EOCD is UInt32)
        var cdOffset: UInt32 = 0
        for i in 0..<4 {
            cdOffset |= UInt32(zipData[eocdOffset + 16 + i]) << (i * 8)
        }
        let cdStart = Int(cdOffset)
        XCTAssertTrue(cdStart < zipData.count)

        // Check Central Directory signature (0x02014B50 -> PK\x01\x02)
        XCTAssertEqual(zipData[cdStart], 0x50)
        XCTAssertEqual(zipData[cdStart + 1], 0x4B)
        XCTAssertEqual(zipData[cdStart + 2], 0x01)
        XCTAssertEqual(zipData[cdStart + 3], 0x02)
    }

    // MARK: - 2. Limits & Validation

    func testZipApiValidationLimits() throws {
        // Empty entries -> 400 bad_request
        XCTAssertThrowsError(try ZipApi.validate(entries: [])) { error in
            guard let apiErr = error as? ApiError else {
                return XCTFail("Expected ApiError")
            }
            XCTAssertEqual(apiErr.status, 400)
            XCTAssertEqual(apiErr.code, "bad_request")
        }

        // Exceeds 65535 entries -> 413 too_large
        let dummy = ZipEntry(path: "a.txt", isDir: false, size: 0, crc32: 0)
        let overflowEntries = [ZipEntry](repeating: dummy, count: 65536)
        XCTAssertThrowsError(try ZipApi.validate(entries: overflowEntries)) { error in
            guard let apiErr = error as? ApiError else {
                return XCTFail("Expected ApiError")
            }
            XCTAssertEqual(apiErr.status, 413)
            XCTAssertEqual(apiErr.code, "too_large")
        }

        // Exceeds 4GB limit -> 413 too_large
        let hugeEntry = ZipEntry(path: "huge.bin", isDir: false, size: Int64(5) * 1024 * 1024 * 1024, crc32: 0)
        XCTAssertThrowsError(try ZipApi.validate(entries: [hugeEntry])) { error in
            guard let apiErr = error as? ApiError else {
                return XCTFail("Expected ApiError")
            }
            XCTAssertEqual(apiErr.status, 413)
            XCTAssertEqual(apiErr.code, "too_large")
        }
    }

    // MARK: - 3. Database zipEntries Generation & Deduplication

    func testZipEntriesGenerationAndDeduplication() throws {
        let dbPath = tempDir + "/test_zip.db"
        let db = try Database(path: dbPath)
        try Schema.migrate(db)
        let store = VaultStore(db: db)

        // Create folder hierarchy
        let folder1 = try store.createFolder(parentId: nil, name: "Folder")
        let subFolder = try store.createFolder(parentId: folder1.id, name: "Sub")
        _ = try store.createFile(parentId: subFolder.id, name: "nested.txt", size: 5, storedSize: 5, mime: "text/plain", codec: 0, crc32: 1234, blobId: "b1", mtime: nil)

        // Create two files at root with the same name logic (or passing ids of duplicate names)
        let f1 = try store.createFile(parentId: folder1.id, name: "item.txt", size: 10, storedSize: 10, mime: "text/plain", codec: 0, crc32: 2345, blobId: "b2", mtime: nil)
        let f2 = try store.createFile(parentId: nil, name: "item.txt", size: 20, storedSize: 20, mime: "text/plain", codec: 0, crc32: 3456, blobId: "b3", mtime: nil)

        // Trashed file should be ignored
        let trashed = try store.createFile(parentId: nil, name: "trashed.txt", size: 10, storedSize: 10, mime: "text/plain", codec: 0, crc32: 4567, blobId: "b4", mtime: nil)
        _ = try store.trash([trashed.id])

        // Query zip entries for folder1 and f2
        let entries = try store.zipEntries(forIds: [folder1.id, f2.id, trashed.id])

        // Trashed file must not appear
        XCTAssertFalse(entries.contains(where: { $0.path.contains("trashed") }))

        let paths = entries.map { $0.path }
        // Folder should include its path and children
        XCTAssertTrue(paths.contains("Folder/"))
        XCTAssertTrue(paths.contains("Folder/Sub/"))
        XCTAssertTrue(paths.contains("Folder/Sub/nested.txt"))
        XCTAssertTrue(paths.contains("Folder/item.txt"))
        XCTAssertTrue(paths.contains("item.txt"))
    }

    // MARK: - 4. HTTP Zip Download & macOS unzip -t Integration

    func testZipDownloadOverHttpAndUnzipTool() throws {
        try setupServer()

        // 1. Create a 2-level folder structure: "archive_test" / "nested"
        let f1Resp = try req(path: "/api/folders", method: "POST", jsonBody: ["name": "archive_test"])
        guard let f1Json = try? JSONSerialization.jsonObject(with: f1Resp.body, options: []) as? [String: Any],
              let f1Id = f1Json["id"] as? String else {
            return XCTFail("Failed to create root folder")
        }

        let f2Resp = try req(path: "/api/folders", method: "POST", jsonBody: ["name": "nested", "parentId": f1Id])
        guard let f2Json = try? JSONSerialization.jsonObject(with: f2Resp.body, options: []) as? [String: Any],
              let f2Id = f2Json["id"] as? String else {
            return XCTFail("Failed to create nested folder")
        }

        // 2. Upload raw file into nested folder
        let rawContent = Data("Uncompressed raw binary content 123456789".utf8)
        try uploadFile(parentId: f2Id, name: "raw_file.bin", data: rawContent, compress: "off")

        // 3. Upload compressible file into root folder
        var textContent = ""
        for i in 0..<500 {
            textContent += "Line \(i): ExVault highly-compressible repetitive log text.\n"
        }
        let textData = Data(textContent.utf8)
        try uploadFile(parentId: f1Id, name: "compressed.txt", data: textData, compress: "auto")

        // 4. Request POST /api/zip with ids=<f1Id>
        let formBody = "ids=\(f1Id)"
        let zipResp = try req(
            path: "/api/zip",
            method: "POST",
            bodyData: Data(formBody.utf8),
            customHeaders: ["Content-Type": "application/x-www-form-urlencoded"]
        )

        XCTAssertEqual(zipResp.status, 200)
        XCTAssertEqual(zipResp.headers["content-type"], "application/zip")

        let disp = zipResp.headers["content-disposition"]
        XCTAssertNotNil(disp)
        XCTAssertTrue(disp?.contains("archive_test.zip") == true)

        let reportedLength = Int(zipResp.headers["content-length"] ?? "0") ?? 0
        XCTAssertEqual(reportedLength, zipResp.body.count)
        XCTAssertTrue(zipResp.body.count > 0)

        // 5. Test with macOS /usr/bin/unzip tool if available
        #if os(macOS)
        let unzipTool = "/usr/bin/unzip"
        if FileManager.default.isExecutableFile(atPath: unzipTool) {
            let zipPath = tempDir + "/test_download.zip"
            let extractDir = tempDir + "/extracted"
            try zipResp.body.write(to: URL(fileURLWithPath: zipPath))
            try FileManager.default.createDirectory(atPath: extractDir, withIntermediateDirectories: true)

            // Test integrity: unzip -t
            let testProcess = Process()
            testProcess.executableURL = URL(fileURLWithPath: unzipTool)
            testProcess.arguments = ["-t", zipPath]
            try testProcess.run()
            testProcess.waitUntilExit()
            XCTAssertEqual(testProcess.terminationStatus, 0, "unzip -t integrity test failed")

            // Extract: unzip -d <extractDir> <zipPath>
            let extProcess = Process()
            extProcess.executableURL = URL(fileURLWithPath: unzipTool)
            extProcess.arguments = ["-d", extractDir, zipPath]
            try extProcess.run()
            extProcess.waitUntilExit()
            XCTAssertEqual(extProcess.terminationStatus, 0, "unzip extract failed")

            // Verify extracted files match original content
            let extractedRawPath = extractDir + "/archive_test/nested/raw_file.bin"
            let extractedRaw = try Data(contentsOf: URL(fileURLWithPath: extractedRawPath))
            XCTAssertEqual(extractedRaw, rawContent)

            let extractedTextPath = extractDir + "/archive_test/compressed.txt"
            let extractedText = try Data(contentsOf: URL(fileURLWithPath: extractedTextPath))
            XCTAssertEqual(extractedText, textData)
        }
        #endif
    }

    // MARK: - Server & HTTP Helpers

    private func setupServer() throws {
        let config = VaultConfig(
            dataDir: tempDir + "/data",
            webRoot: tempDir + "/web",
            port: 0
        )
        try FileManager.default.createDirectory(atPath: config.dataDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: config.webRoot, withIntermediateDirectories: true)

        server = VaultServer(config: config)
        try server.start()
        port = server.port
        XCTAssertTrue(port > 0)

        // Login to obtain exv_sid
        let user = server.currentCredentials.username
        let pass = server.currentCredentials.password
        let authResp = try req(
            path: "/api/auth/login",
            method: "POST",
            jsonBody: ["username": user, "password": pass]
        )
        XCTAssertEqual(authResp.status, 200)
        let cookies = authResp.cookies
        guard let sid = cookies["exv_sid"] else {
            XCTFail("Missing exv_sid cookie on login")
            return
        }
        sessionToken = sid
    }

    private func uploadFile(parentId: String?, name: String, data: Data, compress: String) throws {
        var createPayload: [String: Any] = [
            "name": name,
            "size": data.count,
            "mime": "application/octet-stream",
            "compress": compress
        ]
        if let pid = parentId {
            createPayload["parentId"] = pid
        }

        let createResp = try req(path: "/api/upload", method: "POST", jsonBody: createPayload)
        XCTAssertEqual(createResp.status, 201)
        guard let createJson = try? JSONSerialization.jsonObject(with: createResp.body, options: []) as? [String: Any],
              let uploadId = createJson["uploadId"] as? String else {
            XCTFail("Missing uploadId")
            return
        }

        let putResp = try req(
            path: "/api/upload/\(uploadId)?offset=0",
            method: "PUT",
            bodyData: data,
            customHeaders: ["Content-Type": "application/octet-stream"]
        )
        XCTAssertEqual(putResp.status, 200)

        let finResp = try req(path: "/api/upload/\(uploadId)/finish", method: "POST")
        XCTAssertEqual(finResp.status, 202)

        // Poll until done
        for _ in 0..<50 {
            Thread.sleep(forTimeInterval: 0.05)
            let stResp = try req(path: "/api/upload/\(uploadId)")
            if let stJson = try? JSONSerialization.jsonObject(with: stResp.body, options: []) as? [String: Any],
               let state = stJson["state"] as? String {
                if state == "done" {
                    return
                }
                if state == "error" {
                    XCTFail("Upload processing failed: \(stJson["error"] ?? "")")
                    return
                }
            }
        }
        XCTFail("Upload processing timed out")
    }

    private struct TestResponse {
        let status: Int
        let headers: [String: String]
        let cookies: [String: String]
        let body: Data
    }

    private func req(
        path: String,
        method: String = "GET",
        jsonBody: [String: Any]? = nil,
        bodyData: Data? = nil,
        customHeaders: [String: String] = [:]
    ) throws -> TestResponse {
        let url = URL(string: "http://127.0.0.1:\(port)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = method

        for (k, v) in customHeaders {
            request.setValue(v, forHTTPHeaderField: k)
        }

        if !sessionToken.isEmpty && customHeaders["Cookie"] == nil {
            request.setValue("exv_sid=\(sessionToken)", forHTTPHeaderField: "Cookie")
        }

        if let json = jsonBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json, options: [])
        } else if let b = bodyData {
            request.httpBody = b
        }

        let sem = DispatchSemaphore(value: 0)
        var responseStatus = 0
        var responseHeaders: [String: String] = [:]
        var responseCookies: [String: String] = [:]
        var responseBody = Data()
        var reqError: Error?

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.httpShouldSetCookies = false
        sessionConfig.httpCookieAcceptPolicy = .never
        let session = URLSession(configuration: sessionConfig)

        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                reqError = error
            }
            if let http = response as? HTTPURLResponse {
                responseStatus = http.statusCode
                for (k, v) in http.allHeaderFields {
                    if let ks = k as? String, let vs = v as? String {
                        responseHeaders[ks.lowercased()] = vs
                        if ks.lowercased() == "set-cookie" {
                            let parts = vs.split(separator: ";")
                            if let first = parts.first {
                                let kv = first.split(separator: "=", maxSplits: 1)
                                if kv.count == 2 {
                                    responseCookies[String(kv[0]).trimmingCharacters(in: .whitespaces)] = String(kv[1]).trimmingCharacters(in: .whitespaces)
                                }
                            }
                        }
                    }
                }
            }
            if let d = data {
                responseBody = d
            }
            sem.signal()
        }
        task.resume()
        sem.wait()

        if let err = reqError {
            throw err
        }

        return TestResponse(
            status: responseStatus,
            headers: responseHeaders,
            cookies: responseCookies,
            body: responseBody
        )
    }
}
