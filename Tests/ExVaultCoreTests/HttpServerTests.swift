// Unit tests for HttpServer: keep-alive, streaming, connection cap, error codes, and resilience.

import XCTest
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
@testable import ExVaultCore

final class HttpServerTests: XCTestCase {

    private func connectRaw(port: UInt16) throws -> Int32 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr)

        let rc = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if rc < 0 {
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ECONNREFUSED)
        }
        return fd
    }

    private func readOneHttpResponse(fd: Int32) throws -> (status: Int, headers: [String: String], body: Data) {
        var headerBytes = Data()
        var singleByte: UInt8 = 0

        while true {
            let n = read(fd, &singleByte, 1)
            if n <= 0 { break }
            headerBytes.append(singleByte)
            let c = headerBytes.count
            if c >= 4 &&
                headerBytes[c - 4] == 0x0D && headerBytes[c - 3] == 0x0A &&
                headerBytes[c - 2] == 0x0D && headerBytes[c - 1] == 0x0A {
                break
            }
        }

        guard let headerStr = String(data: headerBytes, encoding: .utf8) else {
            return (0, [:], Data())
        }

        let lines = headerStr.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return (0, [:], Data()) }

        let statusParts = lines[0].split(separator: " ")
        let status = statusParts.count >= 2 ? (Int(statusParts[1]) ?? 0) : 0

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let k = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let v = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[k] = v
        }

        var body = Data()
        if let clStr = headers["content-length"], let cl = Int(clStr), cl > 0 {
            var remaining = cl
            var buf = [UInt8](repeating: 0, count: min(remaining, 64 * 1024))
            while remaining > 0 {
                let toRead = min(remaining, buf.count)
                let n = read(fd, &buf, toRead)
                if n <= 0 { break }
                body.append(buf, count: n)
                remaining -= n
            }
        }

        return (status, headers, body)
    }

    private func syncRequest(
        url: URL,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval = 5.0
    ) throws -> (status: Int, headers: [String: String], data: Data) {
        var req = URLRequest(url: url)
        req.httpMethod = method
        for (k, v) in headers {
            req.setValue(v, forHTTPHeaderField: k)
        }
        req.httpBody = body

        let sem = DispatchSemaphore(value: 0)
        var respStatus = 0
        var respHeaders: [String: String] = [:]
        var respData = Data()
        var reqError: Error?

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        let session = URLSession(configuration: config)

        let task = session.dataTask(with: req) { data, response, error in
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
        if sem.wait(timeout: .now() + timeout) == .timedOut {
            task.cancel()
            throw ApiError.internalError("Request timed out")
        }
        if let err = reqError {
            throw err
        }
        return (respStatus, respHeaders, respData)
    }

    func testSimpleGetJson() throws {
        let server = HttpServer(maxConnections: 4) { req in
            XCTAssertEqual(req.method, "GET")
            XCTAssertEqual(req.path, "/api/hello")
            return HttpResponse.json(["greeting": "hello world"])
        }
        let port = try server.start(port: 0)
        defer { server.stop() }

        let url = URL(string: "http://127.0.0.1:\(port)/api/hello")!
        let (status, headers, data) = try syncRequest(url: url)

        XCTAssertEqual(status, 200)
        XCTAssertTrue(headers["content-type"]?.contains("application/json") == true)
        let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        XCTAssertEqual(json?["greeting"] as? String, "hello world")
    }

    func testPostOneMegabyteEcho() throws {
        let oneMB = 1024 * 1024
        let payload = Data([UInt8](repeating: 0x41, count: oneMB))

        let server = HttpServer(maxConnections: 4) { req in
            XCTAssertEqual(req.method, "POST")
            do {
                let data = try req.body.readAll(limit: 2 * 1024 * 1024)
                return HttpResponse.json(["received": data.count])
            } catch {
                return HttpResponse.error(ApiError.internalError(error.localizedDescription))
            }
        }
        let port = try server.start(port: 0)
        defer { server.stop() }

        let url = URL(string: "http://127.0.0.1:\(port)/upload")!
        let (status, _, data) = try syncRequest(url: url, method: "POST", headers: ["Content-Type": "application/octet-stream"], body: payload)

        XCTAssertEqual(status, 200)
        let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        XCTAssertEqual(json?["received"] as? Int, oneMB)
    }

    func testHeadRequestNoBody() throws {
        let server = HttpServer(maxConnections: 4) { req in
            return HttpResponse(status: 200, headers: [("X-Custom", "Val")], body: .data(Data("1234567890".utf8)))
        }
        let port = try server.start(port: 0)
        defer { server.stop() }

        let fd = try connectRaw(port: port)
        defer { close(fd) }

        let reqText = "HEAD /test HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
        try reqText.utf8CString.withUnsafeBufferPointer { cstr in
            try Net.writeFully(fd: fd, cstr.baseAddress!, count: reqText.utf8.count)
        }

        let resp = try readOneHttpResponse(fd: fd)
        XCTAssertEqual(resp.status, 200)
        XCTAssertEqual(resp.headers["content-length"], "10")
        XCTAssertEqual(resp.headers["x-custom"], "Val")
        XCTAssertEqual(resp.body.count, 0) // HEAD must never send body
    }

    func testKeepAliveTwoRequestsOnSameSocket() throws {
        var count = 0
        let server = HttpServer(maxConnections: 4) { req in
            count += 1
            return HttpResponse.json(["req": count])
        }
        let port = try server.start(port: 0)
        defer { server.stop() }

        let fd = try connectRaw(port: port)
        defer { close(fd) }

        // Request 1
        let req1 = "GET /first HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
        try req1.utf8CString.withUnsafeBufferPointer { cstr in
            try Net.writeFully(fd: fd, cstr.baseAddress!, count: req1.utf8.count)
        }
        let resp1 = try readOneHttpResponse(fd: fd)
        XCTAssertEqual(resp1.status, 200)
        XCTAssertEqual(resp1.headers["connection"], "keep-alive")
        let json1 = try JSONSerialization.jsonObject(with: resp1.body, options: []) as? [String: Any]
        XCTAssertEqual(json1?["req"] as? Int, 1)

        // Request 2 on the same socket
        let req2 = "GET /second HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
        try req2.utf8CString.withUnsafeBufferPointer { cstr in
            try Net.writeFully(fd: fd, cstr.baseAddress!, count: req2.utf8.count)
        }
        let resp2 = try readOneHttpResponse(fd: fd)
        XCTAssertEqual(resp2.status, 200)
        XCTAssertEqual(resp2.headers["connection"], "close")
        let json2 = try JSONSerialization.jsonObject(with: resp2.body, options: []) as? [String: Any]
        XCTAssertEqual(json2?["req"] as? Int, 2)
    }

    func testHeaderTooLargeReturns431() throws {
        let server = HttpServer(maxConnections: 4) { _ in HttpResponse.empty(200) }
        let port = try server.start(port: 0)
        defer { server.stop() }

        let fd = try connectRaw(port: port)
        defer { close(fd) }

        // Send a 17KB header
        let bigHeader = String(repeating: "A", count: 17 * 1024)
        let reqText = "GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Big: \(bigHeader)\r\n\r\n"
        try reqText.utf8CString.withUnsafeBufferPointer { cstr in
            try Net.writeFully(fd: fd, cstr.baseAddress!, count: reqText.utf8.count)
        }

        let resp = try readOneHttpResponse(fd: fd)
        XCTAssertEqual(resp.status, 431)
    }

    func testMethodNotAllowedReturns405() throws {
        let server = HttpServer(maxConnections: 4) { _ in HttpResponse.empty(200) }
        let port = try server.start(port: 0)
        defer { server.stop() }

        let fd = try connectRaw(port: port)
        defer { close(fd) }

        let reqText = "PURGE /item HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
        try reqText.utf8CString.withUnsafeBufferPointer { cstr in
            try Net.writeFully(fd: fd, cstr.baseAddress!, count: reqText.utf8.count)
        }

        let resp = try readOneHttpResponse(fd: fd)
        XCTAssertEqual(resp.status, 405)
        XCTAssertTrue(resp.headers["allow"]?.contains("GET") == true)
    }

    func testClientChunkedReturns411() throws {
        let server = HttpServer(maxConnections: 4) { _ in HttpResponse.empty(200) }
        let port = try server.start(port: 0)
        defer { server.stop() }

        let fd = try connectRaw(port: port)
        defer { close(fd) }

        let reqText = "POST /chunked HTTP/1.1\r\nHost: 127.0.0.1\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n"
        try reqText.utf8CString.withUnsafeBufferPointer { cstr in
            try Net.writeFully(fd: fd, cstr.baseAddress!, count: reqText.utf8.count)
        }

        let resp = try readOneHttpResponse(fd: fd)
        XCTAssertEqual(resp.status, 411)
    }

    func testStreamChunkedResponse() throws {
        let sample1 = "Chunk part 1 - "
        let sample2 = "Chunk part 2 - "
        let sample3 = "Chunk part 3 finished."
        let expected = sample1 + sample2 + sample3

        let server = HttpServer(maxConnections: 4) { _ in
            return HttpResponse(
                status: 200,
                headers: [("Content-Type", "text/plain; charset=utf-8")],
                body: .stream(length: nil) { writer in
                    try writer.write(Data(sample1.utf8))
                    try writer.write(Data(sample2.utf8))
                    try writer.write(Data(sample3.utf8))
                }
            )
        }
        let port = try server.start(port: 0)
        defer { server.stop() }

        let url = URL(string: "http://127.0.0.1:\(port)/stream")!
        let (status, headers, data) = try syncRequest(url: url)

        XCTAssertEqual(status, 200)
        XCTAssertEqual(String(data: data, encoding: .utf8), expected)
    }

    func testMaxConnectionsRejection503() throws {
        // maxConnections: 2
        let server = HttpServer(maxConnections: 2) { req in
            // Hold request for 100ms
            Thread.sleep(forTimeInterval: 0.1)
            return HttpResponse.empty(200)
        }
        let port = try server.start(port: 0)
        defer { server.stop() }

        let total = 20
        var statuses = [Int]()
        let lock = NSLock()
        let group = DispatchGroup()

        for _ in 0..<total {
            group.enter()
            DispatchQueue.global().async {
                do {
                    let fd = try self.connectRaw(port: port)
                    defer { close(fd) }
                    let reqText = "GET /busy HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
                    try reqText.utf8CString.withUnsafeBufferPointer { cstr in
                        try Net.writeFully(fd: fd, cstr.baseAddress!, count: reqText.utf8.count)
                    }
                    let resp = try self.readOneHttpResponse(fd: fd)
                    lock.lock()
                    statuses.append(resp.status)
                    lock.unlock()
                } catch {
                    // Socket might be closed immediately
                }
                group.leave()
            }
        }

        _ = group.wait(timeout: .now() + 5.0)

        // At least one 503 should be received and server should not deadlock
        let busyCount = statuses.filter { $0 == 503 }.count
        XCTAssertGreaterThan(busyCount, 0, "Some requests must receive 503 when overloaded")
    }

    func testClientAbortsStreamServerSurvives() throws {
        let server = HttpServer(maxConnections: 4) { req in
            if req.path == "/huge" {
                return HttpResponse(
                    status: 200,
                    headers: [],
                    body: .stream(length: 10 * 1024 * 1024) { writer in
                        let chunk = Data([UInt8](repeating: 0x55, count: 64 * 1024))
                        for _ in 0..<160 {
                            try writer.write(chunk)
                            Thread.sleep(forTimeInterval: 0.01)
                        }
                    }
                )
            } else {
                return HttpResponse.json(["status": "alive"])
            }
        }
        let port = try server.start(port: 0)
        defer { server.stop() }

        // Client 1: connects, requests /huge, reads 1KB, and aborts (close)
        let fd1 = try connectRaw(port: port)
        let req1 = "GET /huge HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
        try req1.utf8CString.withUnsafeBufferPointer { cstr in
            try Net.writeFully(fd: fd1, cstr.baseAddress!, count: req1.utf8.count)
        }
        var discard = [UInt8](repeating: 0, count: 1024)
        _ = read(fd1, &discard, 1024)
        close(fd1) // Abrupt close

        Thread.sleep(forTimeInterval: 0.05)

        // Client 2: requests /alive, server must still function properly
        let url = URL(string: "http://127.0.0.1:\(port)/alive")!
        let (status, _, data) = try syncRequest(url: url)
        XCTAssertEqual(status, 200)
        let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        XCTAssertEqual(json?["status"] as? String, "alive")
    }

    func testStopAndRestartOnAnotherPort() throws {
        let server = HttpServer(maxConnections: 4) { _ in
            return HttpResponse.json(["ok": true])
        }

        let port1 = try server.start(port: 0)
        XCTAssertGreaterThan(port1, 0)

        let url1 = URL(string: "http://127.0.0.1:\(port1)/test")!
        let (status1, _, _) = try syncRequest(url: url1)
        XCTAssertEqual(status1, 200)

        server.stop()
        XCTAssertEqual(server.boundPort, 0)

        let port2 = try server.start(port: 0)
        XCTAssertGreaterThan(port2, 0)

        let url2 = URL(string: "http://127.0.0.1:\(port2)/test")!
        let (status2, _, _) = try syncRequest(url: url2)
        XCTAssertEqual(status2, 200)
    }

    func testObsFoldAndHeaderCount() throws {
        let server = HttpServer(maxConnections: 4) { _ in HttpResponse.empty(200) }
        let port = try server.start(port: 0)
        defer { server.stop() }

        // Obs-fold test
        let fd1 = try connectRaw(port: port)
        let reqObsFold = "GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Fold: start\r\n continuing\r\nConnection: close\r\n\r\n"
        try reqObsFold.utf8CString.withUnsafeBufferPointer { cstr in
            try Net.writeFully(fd: fd1, cstr.baseAddress!, count: reqObsFold.utf8.count)
        }
        let resp1 = try readOneHttpResponse(fd: fd1)
        close(fd1)
        XCTAssertEqual(resp1.status, 400)

        // Too many headers (>64)
        let fd2 = try connectRaw(port: port)
        var manyHeaders = "GET / HTTP/1.1\r\nHost: 127.0.0.1\r\n"
        for i in 0..<70 {
            manyHeaders += "X-Header-\(i): val\r\n"
        }
        manyHeaders += "Connection: close\r\n\r\n"
        try manyHeaders.utf8CString.withUnsafeBufferPointer { cstr in
            try Net.writeFully(fd: fd2, cstr.baseAddress!, count: manyHeaders.utf8.count)
        }
        let resp2 = try readOneHttpResponse(fd: fd2)
        close(fd2)
        XCTAssertEqual(resp2.status, 431)
    }
}
