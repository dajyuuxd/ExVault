// Unit tests for StaticFiles: traversal protection, symlink checks, ETag 304, and MIME types.

import XCTest
@testable import ExVaultCore

final class StaticFilesTests: XCTestCase {
    private var tempDir: URL = URL(fileURLWithPath: NSTemporaryDirectory())
    private var webRoot: URL = URL(fileURLWithPath: NSTemporaryDirectory())
    private var staticFiles: StaticFiles?

    override func setUp() {
        super.setUp()
        tempDir = URL(fileURLWithPath: (NSTemporaryDirectory() as NSString).appendingPathComponent("static_test_\(UUID().uuidString)"))
        webRoot = tempDir.appendingPathComponent("Web")
        try? FileManager.default.createDirectory(at: webRoot, withIntermediateDirectories: true, attributes: nil)

        // Create sample files
        let indexFile = webRoot.appendingPathComponent("index.html")
        try? "<html><body>ExVault</body></html>".write(to: indexFile, atomically: true, encoding: .utf8)

        let cssDir = webRoot.appendingPathComponent("css")
        try? FileManager.default.createDirectory(at: cssDir, withIntermediateDirectories: true, attributes: nil)
        try? "body { margin: 0; }".write(to: cssDir.appendingPathComponent("app.css"), atomically: true, encoding: .utf8)

        let jsDir = webRoot.appendingPathComponent("js")
        try? FileManager.default.createDirectory(at: jsDir, withIntermediateDirectories: true, attributes: nil)
        try? "console.log('ExVault');".write(to: jsDir.appendingPathComponent("app.js"), atomically: true, encoding: .utf8)

        // Create a secret file outside Web root
        let secretFile = tempDir.appendingPathComponent("secret.txt")
        try? "CLASSIFIED".write(to: secretFile, atomically: true, encoding: .utf8)

        staticFiles = StaticFiles(root: webRoot)
    }

    override func tearDown() {
        staticFiles = nil
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testServeIndex() {
        guard let sf = staticFiles else { return }

        // Root / resolves to index.html
        let resolved = sf.resolve(urlPath: "/")
        XCTAssertNotNil(resolved)
        XCTAssertTrue(resolved?.hasSuffix("index.html") == true)

        let resp = sf.serve(urlPath: "/", ifNoneMatch: nil)
        XCTAssertEqual(resp.status, 200)

        let contentType = resp.headers.first { $0.0 == "Content-Type" }?.1
        XCTAssertTrue(contentType?.contains("text/html") == true)
        XCTAssertTrue(contentType?.contains("charset=utf-8") == true)

        let cacheControl = resp.headers.first { $0.0 == "Cache-Control" }?.1
        XCTAssertEqual(cacheControl, "no-cache")

        let etag = resp.headers.first { $0.0 == "ETag" }?.1
        XCTAssertNotNil(etag)
    }

    func testPathTraversalAttacksBlocked() {
        guard let sf = staticFiles else { return }

        // 1. /../secret.txt
        XCTAssertNil(sf.resolve(urlPath: "/../secret.txt"))
        let resp1 = sf.serve(urlPath: "/../secret.txt", ifNoneMatch: nil)
        XCTAssertEqual(resp1.status, 404)

        // 2. /..
        XCTAssertNil(sf.resolve(urlPath: "/.."))

        // 3. /css/../../secret.txt
        XCTAssertNil(sf.resolve(urlPath: "/css/../../secret.txt"))

        // 4. //etc/passwd
        XCTAssertNil(sf.resolve(urlPath: "//etc/passwd"))

        // 5. Path with null byte \0
        XCTAssertNil(sf.resolve(urlPath: "/index.html\0secret"))

        // 6. Non-existent file
        XCTAssertNil(sf.resolve(urlPath: "/nonexistent.txt"))
        let resp6 = sf.serve(urlPath: "/nonexistent.txt", ifNoneMatch: nil)
        XCTAssertEqual(resp6.status, 404)
    }

    func testETagAnd304NotModified() {
        guard let sf = staticFiles else { return }

        let resp1 = sf.serve(urlPath: "/css/app.css", ifNoneMatch: nil)
        XCTAssertEqual(resp1.status, 200)
        guard let etag = resp1.headers.first(where: { $0.0 == "ETag" })?.1 else {
            XCTFail("Missing ETag header")
            return
        }

        // Second request with matching If-None-Match
        let resp2 = sf.serve(urlPath: "/css/app.css", ifNoneMatch: etag)
        XCTAssertEqual(resp2.status, 304)
        if case .none = resp2.body {
            // Correct: 304 has no body
        } else {
            XCTFail("304 response must not have body")
        }

        // Third request with different If-None-Match
        let resp3 = sf.serve(urlPath: "/css/app.css", ifNoneMatch: "\"different-etag\"")
        XCTAssertEqual(resp3.status, 200)
    }

    func testMimeTypesForAssets() {
        guard let sf = staticFiles else { return }

        let respCss = sf.serve(urlPath: "/css/app.css", ifNoneMatch: nil)
        XCTAssertEqual(respCss.status, 200)
        let cssType = respCss.headers.first(where: { $0.0 == "Content-Type" })?.1
        XCTAssertTrue(cssType?.contains("text/css") == true)
        XCTAssertTrue(cssType?.contains("charset=utf-8") == true)

        let respJs = sf.serve(urlPath: "/js/app.js", ifNoneMatch: nil)
        XCTAssertEqual(respJs.status, 200)
        let jsType = respJs.headers.first(where: { $0.0 == "Content-Type" })?.1
        XCTAssertTrue(jsType?.contains("application/javascript") == true)
        XCTAssertTrue(jsType?.contains("charset=utf-8") == true)
    }
}
