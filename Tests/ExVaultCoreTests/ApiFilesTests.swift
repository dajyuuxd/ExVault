// Integration tests for UploadApi and FilesApi: chunked upload, content streaming, Range headers, ETag 304, thumbnails, and error handling.

import XCTest
@testable import ExVaultCore

final class ApiFilesTests: XCTestCase {
    private var tempDir: URL = URL(fileURLWithPath: NSTemporaryDirectory())
    private var server: VaultServer?
    private var port: UInt16 = 0
    private var session: URLSession = URLSession.shared
    private var authCookie: String = ""

    override func setUp() {
        super.setUp()
        tempDir = URL(fileURLWithPath: (NSTemporaryDirectory() as NSString).appendingPathComponent("apifiles_test_\(UUID().uuidString)"))
        let dataDir = tempDir.appendingPathComponent("Data")
        let webRoot = tempDir.appendingPathComponent("Web")

        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true, attributes: nil)
        try? FileManager.default.createDirectory(at: webRoot, withIntermediateDirectories: true, attributes: nil)

        let cfg = VaultConfig(
            dataDir: dataDir,
            webRoot: webRoot,
            port: 0,
            maxConnections: 8,
            maxSessions: 3,
            reserveFreeBytes: 10 * 1024 * 1024,
            uploadChunkSize: 100_000
        )

        do {
            let s = try VaultServer(config: cfg)
            try s.start()
            self.server = s
            self.port = s.boundPort

            let sessionConfig = URLSessionConfiguration.ephemeral
            sessionConfig.timeoutIntervalForRequest = 5.0
            sessionConfig.httpShouldSetCookies = false
            sessionConfig.httpCookieAcceptPolicy = .never
            self.session = URLSession(configuration: sessionConfig)

            // Perform login
            let l = try req(
                path: "/api/login",
                method: "POST",
                jsonBody: ["username": s.credentials.username, "password": s.credentials.password]
            )
            guard let setCookie = l.headers["set-cookie"] else {
                XCTFail("Login failed to provide Set-Cookie")
                return
            }
            self.authCookie = String(setCookie.split(separator: ";").first!)
        } catch {
            XCTFail("Failed to initialize server in setUp: \(error)")
        }
    }

    override func tearDown() {
        server?.stop()
        server = nil
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func req(
        path: String,
        method: String = "GET",
        jsonBody: [String: Any]? = nil,
        rawBody: Data? = nil,
        customHeaders: [String: String] = [:]
    ) throws -> (status: Int, headers: [String: String], body: Data, json: [String: Any]?) {
        let url = URL(string: "http://127.0.0.1:\(port)\(path)")!
        var r = URLRequest(url: url)
        r.httpMethod = method

        if !authCookie.isEmpty {
            r.setValue(authCookie, forHTTPHeaderField: "Cookie")
        }

        if let j = jsonBody {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONSerialization.data(withJSONObject: j, options: [])
        } else if let b = rawBody {
            r.httpBody = b
        }

        for (k, v) in customHeaders {
            r.setValue(v, forHTTPHeaderField: k)
        }

        let sem = DispatchSemaphore(value: 0)
        var respStatus = 0
        var respHeaders: [String: String] = [:]
        var respData = Data()
        var reqError: Error?

        let task = session.dataTask(with: r) { data, response, error in
            if let error = error {
                reqError = error
            }
            if let http = response as? HTTPURLResponse {
                respStatus = http.statusCode
                for (k, v) in http.allHeaderFields {
                    if let ks = k as? String, let vs = v as? String {
                        respHeaders[ks.lowercased()] = vs
                    }
                }
            }
            if let d = data {
                respData = d
            }
            sem.signal()
        }
        task.resume()
        _ = sem.wait(timeout: .now() + 5.0)

        if let err = reqError {
            throw err
        }

        let jsonObj = (try? JSONSerialization.jsonObject(with: respData, options: [])) as? [String: Any]
        return (respStatus, respHeaders, respData, jsonObj)
    }

    func testUploadTextFileWithCompressionAndDownload() throws {
        // 3 chunks of repeating text, 300,000 bytes total
        let chunkCount = 3
        let chunkSize = 100_000
        let totalSize = Int64(chunkCount * chunkSize)
        let sample = "ExVault upload api compression test line with Vietnamese characters: Báo cáo tài chính.\n"
        var text = ""
        while text.utf8.count < chunkSize {
            text.append(sample)
        }
        let chunkData = Data(text.utf8.prefix(chunkSize))
        var fullData = Data()
        for _ in 0..<chunkCount {
            fullData.append(chunkData)
        }

        // 1. Create upload with Vietnamese name
        let fileName = "Báo cáo tài chính.txt"
        let createResp = try req(
            path: "/api/upload",
            method: "POST",
            jsonBody: [
                "name": fileName,
                "size": totalSize,
                "mime": "text/plain",
                "compress": "auto"
            ]
        )
        XCTAssertEqual(createResp.status, 201)
        guard let uploadId = createResp.json?["uploadId"] as? String else {
            XCTFail("Missing uploadId")
            return
        }

        // 2. Upload chunks with PUT
        for i in 0..<chunkCount {
            let offset = Int64(i * chunkSize)
            let putResp = try req(
                path: "/api/upload/\(uploadId)?offset=\(offset)",
                method: "PUT",
                rawBody: chunkData,
                customHeaders: [
                    "Content-Type": "application/octet-stream",
                    "Content-Length": "\(chunkData.count)"
                ]
            )
            XCTAssertEqual(putResp.status, 200)
            XCTAssertEqual(putResp.json?["offset"] as? Int64, offset + Int64(chunkSize))
        }

        // 3. Finish upload
        let finishResp = try req(
            path: "/api/upload/\(uploadId)/finish",
            method: "POST"
        )
        XCTAssertTrue(finishResp.status == 200 || finishResp.status == 202)

        // Poll if processing
        var nodeObj: [String: Any]? = finishResp.json?["node"] as? [String: Any]
        var attempts = 0
        while nodeObj == nil && attempts < 50 {
            attempts += 1
            Thread.sleep(forTimeInterval: 0.05)
            let poll = try req(path: "/api/upload/\(uploadId)")
            if poll.json?["state"] as? String == "done" {
                nodeObj = poll.json?["node"] as? [String: Any]
                break
            }
        }

        XCTAssertNotNil(nodeObj, "Upload processing should complete and produce node")
        let nodeId = nodeObj?["id"] as! String
        XCTAssertEqual(nodeObj?["codec"] as? String, "zlib", "Text file must be compressed with zlib")

        // 4. Download content with dl=1
        let dlResp = try req(path: "/api/files/\(nodeId)/content?dl=1")
        XCTAssertEqual(dlResp.status, 200)
        XCTAssertEqual(dlResp.headers["content-length"], "\(totalSize)")
        XCTAssertEqual(dlResp.headers["accept-ranges"], "none")
        XCTAssertEqual(dlResp.body, fullData, "Decompressed content must match original full data")

        // Verify Content-Disposition with RFC 5987 filename*
        let disp = dlResp.headers["content-disposition"]
        XCTAssertNotNil(disp)
        XCTAssertTrue(disp?.hasPrefix("attachment") == true)
        XCTAssertTrue(disp?.contains("filename*=") == true)

        // 5. ETag & If-None-Match
        guard let etag = dlResp.headers["etag"] else {
            XCTFail("Missing ETag header")
            return
        }
        let cachedResp = try req(
            path: "/api/files/\(nodeId)/content",
            customHeaders: ["If-None-Match": etag]
        )
        XCTAssertEqual(cachedResp.status, 304)
        XCTAssertEqual(cachedResp.body.count, 0)

        // 6. HEAD request
        let headResp = try req(path: "/api/files/\(nodeId)/content", method: "HEAD")
        XCTAssertEqual(headResp.status, 200)
        XCTAssertEqual(headResp.headers["content-length"], "\(totalSize)")
        XCTAssertEqual(headResp.body.count, 0)
    }

    func testUploadRawBinaryFileAndRangeRequests() throws {
        // Create 100 bytes of random data for raw binary file
        let size = 100
        var bytes = [UInt8](repeating: 0, count: size)
        for i in 0..<size {
            bytes[i] = UInt8(i)
        }
        let data = Data(bytes)

        // 1. Create upload (compress: off to force raw)
        let createResp = try req(
            path: "/api/upload",
            method: "POST",
            jsonBody: [
                "name": "data.bin",
                "size": size,
                "mime": "application/octet-stream",
                "compress": "off"
            ]
        )
        XCTAssertEqual(createResp.status, 201)
        let uploadId = createResp.json?["uploadId"] as! String

        // 2. Upload single chunk
        let putResp = try req(
            path: "/api/upload/\(uploadId)?offset=0",
            method: "PUT",
            rawBody: data,
            customHeaders: ["Content-Length": "\(size)"]
        )
        XCTAssertEqual(putResp.status, 200)

        // 3. Finish
        let finishResp = try req(path: "/api/upload/\(uploadId)/finish", method: "POST")
        var nodeObj = finishResp.json?["node"] as? [String: Any]
        var attempts = 0
        while nodeObj == nil && attempts < 50 {
            attempts += 1
            Thread.sleep(forTimeInterval: 0.05)
            let poll = try req(path: "/api/upload/\(uploadId)")
            if poll.json?["state"] as? String == "done" {
                nodeObj = poll.json?["node"] as? [String: Any]
                break
            }
        }
        XCTAssertNotNil(nodeObj)
        let nodeId = nodeObj?["id"] as! String
        XCTAssertEqual(nodeObj?["codec"] as? String, "raw")

        // 4. Test Range: bytes=10-19 -> 206 with exactly 10 bytes (bytes 10 through 19)
        let range1 = try req(
            path: "/api/files/\(nodeId)/content",
            customHeaders: ["Range": "bytes=10-19"]
        )
        XCTAssertEqual(range1.status, 206)
        XCTAssertEqual(range1.headers["content-length"], "10")
        XCTAssertEqual(range1.headers["content-range"], "bytes 10-19/100")
        XCTAssertEqual(range1.body, data.subdata(in: 10..<20))

        // 5. Test Range: bytes=-5 (last 5 bytes: 95 through 99)
        let range2 = try req(
            path: "/api/files/\(nodeId)/content",
            customHeaders: ["Range": "bytes=-5"]
        )
        XCTAssertEqual(range2.status, 206)
        XCTAssertEqual(range2.headers["content-length"], "5")
        XCTAssertEqual(range2.headers["content-range"], "bytes 95-99/100")
        XCTAssertEqual(range2.body, data.subdata(in: 95..<100))

        // 6. Test Range: bytes=999999999- -> 416
        let range3 = try req(
            path: "/api/files/\(nodeId)/content",
            customHeaders: ["Range": "bytes=999999999-"]
        )
        XCTAssertEqual(range3.status, 416)
        XCTAssertEqual(range3.headers["content-range"], "bytes */100")

        // 7. Test download when trashed -> 404
        _ = try req(path: "/api/nodes/trash", method: "POST", jsonBody: ["ids": [nodeId]])
        let trashedGet = try req(path: "/api/files/\(nodeId)/content")
        XCTAssertEqual(trashedGet.status, 404)
    }

    func testUploadVideoGenericMimeResolvesToVideoMp4() throws {
        let size = 64
        let dummyData = Data(repeating: 0x00, count: size)

        let createResp = try req(
            path: "/api/upload",
            method: "POST",
            jsonBody: [
                "name": "sample_clip.mp4",
                "size": size,
                "mime": "application/octet-stream",
                "compress": "auto"
            ]
        )
        XCTAssertEqual(createResp.status, 201)
        let uploadId = createResp.json?["uploadId"] as! String

        let putResp = try req(
            path: "/api/upload/\(uploadId)?offset=0",
            method: "PUT",
            rawBody: dummyData,
            customHeaders: ["Content-Length": "\(size)"]
        )
        XCTAssertEqual(putResp.status, 200)

        _ = try req(path: "/api/upload/\(uploadId)/finish", method: "POST")
        var nodeObj: [String: Any]?
        for _ in 0..<50 {
            Thread.sleep(forTimeInterval: 0.05)
            let poll = try req(path: "/api/upload/\(uploadId)")
            if poll.json?["state"] as? String == "done" {
                nodeObj = poll.json?["node"] as? [String: Any]
                break
            }
        }
        XCTAssertNotNil(nodeObj)
        let nodeId = nodeObj?["id"] as! String

        // Node in database should have effective mime video/mp4
        XCTAssertEqual(nodeObj?["mime"] as? String, "video/mp4")

        // Streaming GET /api/files/:id/content should return Content-Type: video/mp4
        let getResp = try req(
            path: "/api/files/\(nodeId)/content",
            customHeaders: ["Range": "bytes=0-1"]
        )
        XCTAssertEqual(getResp.status, 206)
        XCTAssertEqual(getResp.headers["content-type"], "video/mp4")
        XCTAssertEqual(getResp.headers["content-length"], "2")
        XCTAssertEqual(getResp.headers["content-range"], "bytes 0-1/64")
    }

    func testThumbnailManagement() throws {
        // Create an empty file first
        let f = try req(
            path: "/api/upload",
            method: "POST",
            jsonBody: ["name": "image.jpg", "size": 0, "mime": "image/jpeg"]
        )
        let uploadId = f.json?["uploadId"] as! String
        _ = try req(path: "/api/upload/\(uploadId)/finish", method: "POST")
        Thread.sleep(forTimeInterval: 0.05)
        let info = try req(path: "/api/upload/\(uploadId)")
        let nodeObj = info.json?["node"] as! [String: Any]
        let nodeId = nodeObj["id"] as! String

        // GET thumb before PUT -> 404
        let getBefore = try req(path: "/api/files/\(nodeId)/thumb")
        XCTAssertEqual(getBefore.status, 404)

        // PUT thumb with invalid magic (not 0xFF 0xD8) -> 400
        let badThumb = Data([0x00, 0x01, 0x02, 0x03])
        let putBad = try req(
            path: "/api/files/\(nodeId)/thumb",
            method: "PUT",
            rawBody: badThumb,
            customHeaders: ["Content-Length": "\(badThumb.count)"]
        )
        XCTAssertEqual(putBad.status, 400)

        // PUT valid JPEG thumbnail (SOI marker 0xFF 0xD8)
        var goodThumb = Data([0xFF, 0xD8])
        goodThumb.append(contentsOf: [UInt8](repeating: 0x20, count: 500))
        let putGood = try req(
            path: "/api/files/\(nodeId)/thumb",
            method: "PUT",
            rawBody: goodThumb,
            customHeaders: ["Content-Length": "\(goodThumb.count)"]
        )
        XCTAssertEqual(putGood.status, 204)

        // GET thumb after PUT -> 200 image/jpeg
        let getAfter = try req(path: "/api/files/\(nodeId)/thumb")
        XCTAssertEqual(getAfter.status, 200)
        XCTAssertEqual(getAfter.headers["content-type"], "image/jpeg")
        XCTAssertEqual(getAfter.body, goodThumb)
    }

    func testUploadOffsetMismatchAndResume() throws {
        let size = 1000
        let createResp = try req(
            path: "/api/upload",
            method: "POST",
            jsonBody: ["name": "resume.bin", "size": size, "mime": ""]
        )
        let uploadId = createResp.json?["uploadId"] as! String

        // Send wrong offset 500 -> 409 offset_mismatch with current offset 0
        let wrongOffset = try req(
            path: "/api/upload/\(uploadId)?offset=500",
            method: "PUT",
            rawBody: Data(repeating: 0x41, count: 500),
            customHeaders: ["Content-Length": "500"]
        )
        XCTAssertEqual(wrongOffset.status, 409)
        let err = wrongOffset.json?["error"] as? [String: Any]
        XCTAssertEqual(err?["code"] as? String, "offset_mismatch")
        XCTAssertEqual(err?["offset"] as? Int64, 0)

        // Send correct offset 0
        let chunk1 = Data(repeating: 0x41, count: 500)
        let correctOffset1 = try req(
            path: "/api/upload/\(uploadId)?offset=0",
            method: "PUT",
            rawBody: chunk1,
            customHeaders: ["Content-Length": "500"]
        )
        XCTAssertEqual(correctOffset1.status, 200)
        XCTAssertEqual(correctOffset1.json?["offset"] as? Int64, 500)

        // Send second chunk at offset 500
        let chunk2 = Data(repeating: 0x42, count: 500)
        let correctOffset2 = try req(
            path: "/api/upload/\(uploadId)?offset=500",
            method: "PUT",
            rawBody: chunk2,
            customHeaders: ["Content-Length": "500"]
        )
        XCTAssertEqual(correctOffset2.status, 200)
        XCTAssertEqual(correctOffset2.json?["offset"] as? Int64, 1000)

        // Finish
        let finish = try req(path: "/api/upload/\(uploadId)/finish", method: "POST")
        XCTAssertTrue(finish.status == 200 || finish.status == 202)
    }
}
