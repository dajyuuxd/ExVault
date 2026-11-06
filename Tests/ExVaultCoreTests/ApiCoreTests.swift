// Integration tests for core API endpoints: Auth, Nodes, Tags, Trash, Search, and Stats over HTTP.

import XCTest
@testable import ExVaultCore

final class ApiCoreTests: XCTestCase {
    private var tempDir: URL = URL(fileURLWithPath: NSTemporaryDirectory())
    private var server: VaultServer?
    private var port: UInt16 = 0
    private var session: URLSession = URLSession.shared

    override func setUp() {
        super.setUp()
        tempDir = URL(fileURLWithPath: (NSTemporaryDirectory() as NSString).appendingPathComponent("apicore_test_\(UUID().uuidString)"))
        let dataDir = tempDir.appendingPathComponent("Data")
        let webRoot = tempDir.appendingPathComponent("Web")

        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true, attributes: nil)
        try? FileManager.default.createDirectory(at: webRoot, withIntermediateDirectories: true, attributes: nil)

        // Sample static web files
        try? "<html><body>ExVault Web</body></html>".write(to: webRoot.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        let cssDir = webRoot.appendingPathComponent("css")
        try? FileManager.default.createDirectory(at: cssDir, withIntermediateDirectories: true, attributes: nil)
        try? "body { background: #fff; }".write(to: cssDir.appendingPathComponent("app.css"), atomically: true, encoding: .utf8)

        let cfg = VaultConfig(
            dataDir: dataDir,
            webRoot: webRoot,
            port: 0,
            maxConnections: 8,
            maxSessions: 3,
            reserveFreeBytes: 10 * 1024 * 1024,
            uploadChunkSize: 1024 * 1024
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
        } catch {
            XCTFail("Failed to start VaultServer in setUp: \(error)")
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
        cookie: String? = nil,
        customHeaders: [String: String] = [:]
    ) throws -> (status: Int, headers: [String: String], body: Data, json: [String: Any]?) {
        let url = URL(string: "http://127.0.0.1:\(port)\(path)")!
        var r = URLRequest(url: url)
        r.httpMethod = method

        if let cookie = cookie {
            r.setValue(cookie, forHTTPHeaderField: "Cookie")
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

    private func extractCookie(from headers: [String: String]) -> String? {
        guard let setCookie = headers["set-cookie"] else { return nil }
        let parts = setCookie.split(separator: ";")
        return parts.first.map(String.init)
    }

    func testAuthEndpoints() throws {
        guard let s = server else { return }

        // 1. Health check (no auth needed)
        let health = try req(path: "/api/health")
        XCTAssertEqual(health.status, 200)
        XCTAssertEqual(health.json?["ok"] as? Bool, true)
        XCTAssertEqual(health.json?["version"] as? String, "1.0.2")

        // 2. Login wrong password -> 401
        let badLogin = try req(
            path: "/api/login",
            method: "POST",
            jsonBody: ["username": s.credentials.username, "password": "wrongpassword"]
        )
        XCTAssertEqual(badLogin.status, 401)
        let badErr = badLogin.json?["error"] as? [String: Any]
        XCTAssertEqual(badErr?["code"] as? String, "bad_credentials")

        // 3. Rate limiting after 5 consecutive failures
        for _ in 0..<4 {
            _ = try req(
                path: "/api/login",
                method: "POST",
                jsonBody: ["username": s.credentials.username, "password": "wrongpassword"]
            )
        }
        let rateLimited = try req(
            path: "/api/login",
            method: "POST",
            jsonBody: ["username": s.credentials.username, "password": "wrongpassword"]
        )
        XCTAssertEqual(rateLimited.status, 429)
        XCTAssertNotNil(rateLimited.headers["retry-after"])

        // Reset limiter for this test
        s.limiter.recordSuccess(ip: "127.0.0.1")

        // 4. Correct login -> 204 + Set-Cookie
        let goodLogin = try req(
            path: "/api/login",
            method: "POST",
            jsonBody: ["username": s.credentials.username, "password": s.credentials.password]
        )
        XCTAssertEqual(goodLogin.status, 204)
        guard let cookie = extractCookie(from: goodLogin.headers) else {
            XCTFail("Missing Set-Cookie on successful login")
            return
        }
        XCTAssertTrue(goodLogin.headers["set-cookie"]?.contains("HttpOnly") == true)
        XCTAssertTrue(goodLogin.headers["set-cookie"]?.contains("SameSite=Strict") == true)

        // 5. GET /api/me without cookie -> 401
        let meNoAuth = try req(path: "/api/me")
        XCTAssertEqual(meNoAuth.status, 401)

        // 6. GET /api/me with cookie -> 200
        let meAuth = try req(path: "/api/me", cookie: cookie)
        XCTAssertEqual(meAuth.status, 200)
        XCTAssertEqual(meAuth.json?["username"] as? String, s.credentials.username)
        XCTAssertEqual(meAuth.json?["chunkSize"] as? Int, 1024 * 1024)

        // 7. Logout -> 204 + Cookie Max-Age=0
        let logout = try req(path: "/api/logout", method: "POST", cookie: cookie)
        XCTAssertEqual(logout.status, 204)
        XCTAssertTrue(logout.headers["set-cookie"]?.contains("Max-Age=0") == true)

        // 8. Subsequent call with invalidated cookie -> 401
        let meAfterLogout = try req(path: "/api/me", cookie: cookie)
        XCTAssertEqual(meAfterLogout.status, 401)
    }

    func testSessionStoreEvictionOnMaxSessions() throws {
        guard let s = server else { return }

        // Login session 1
        let l1 = try req(path: "/api/login", method: "POST", jsonBody: ["username": s.credentials.username, "password": s.credentials.password])
        let c1 = extractCookie(from: l1.headers)!

        // Login session 2
        let l2 = try req(path: "/api/login", method: "POST", jsonBody: ["username": s.credentials.username, "password": s.credentials.password])
        let c2 = extractCookie(from: l2.headers)!

        // Login session 3
        let l3 = try req(path: "/api/login", method: "POST", jsonBody: ["username": s.credentials.username, "password": s.credentials.password])
        let c3 = extractCookie(from: l3.headers)!

        XCTAssertEqual(try req(path: "/api/me", cookie: c1).status, 200)
        XCTAssertEqual(try req(path: "/api/me", cookie: c2).status, 200)
        XCTAssertEqual(try req(path: "/api/me", cookie: c3).status, 200)

        // Login session 4 (exceeding maxSessions=3) -> session 1 evicted
        let l4 = try req(path: "/api/login", method: "POST", jsonBody: ["username": s.credentials.username, "password": s.credentials.password])
        let c4 = extractCookie(from: l4.headers)!

        XCTAssertEqual(try req(path: "/api/me", cookie: c1).status, 401, "Session 1 should be evicted")
        XCTAssertEqual(try req(path: "/api/me", cookie: c2).status, 200)
        XCTAssertEqual(try req(path: "/api/me", cookie: c3).status, 200)
        XCTAssertEqual(try req(path: "/api/me", cookie: c4).status, 200)
    }

    func testStaticFilesServingWithoutAuth() throws {
        // GET / -> 200 index.html
        let indexResp = try req(path: "/")
        XCTAssertEqual(indexResp.status, 200)
        XCTAssertTrue(String(data: indexResp.body, encoding: .utf8)?.contains("ExVault Web") == true)

        // GET /css/app.css -> 200 css
        let cssResp = try req(path: "/css/app.css")
        XCTAssertEqual(cssResp.status, 200)
        XCTAssertTrue(cssResp.headers["content-type"]?.contains("text/css") == true)
    }

    func testNodeHierarchyAndFolderOperations() throws {
        guard let s = server else { return }
        let l = try req(path: "/api/login", method: "POST", jsonBody: ["username": s.credentials.username, "password": s.credentials.password])
        let cookie = extractCookie(from: l.headers)!

        // 1. Create folder "Documents" at root
        let f1 = try req(
            path: "/api/folders",
            method: "POST",
            jsonBody: ["parentId": "root", "name": "Documents"],
            cookie: cookie
        )
        XCTAssertEqual(f1.status, 201)
        let docsId = f1.json?["id"] as? String
        XCTAssertNotNil(docsId)

        // 2. Create folder "Photos" at root
        let f2 = try req(
            path: "/api/folders",
            method: "POST",
            jsonBody: ["parentId": "root", "name": "Photos"],
            cookie: cookie
        )
        XCTAssertEqual(f2.status, 201)
        let photosId = f2.json?["id"] as? String
        XCTAssertNotNil(photosId)

        // 3. List root nodes -> contains Documents and Photos
        let rootList = try req(path: "/api/nodes?parent=root", cookie: cookie)
        XCTAssertEqual(rootList.status, 200)
        let items = rootList.json?["items"] as? [[String: Any]]
        XCTAssertEqual(items?.count, 2)

        // 4. Create nested folder inside Documents
        let f3 = try req(
            path: "/api/folders",
            method: "POST",
            jsonBody: ["parentId": docsId!, "name": "Invoices"],
            cookie: cookie
        )
        XCTAssertEqual(f3.status, 201)
        let invoicesId = f3.json?["id"] as? String
        XCTAssertNotNil(invoicesId)

        // 5. List Documents -> contains Invoices & path breadcrumb
        let docsList = try req(path: "/api/nodes?parent=\(docsId!)", cookie: cookie)
        XCTAssertEqual(docsList.status, 200)
        let docsItems = docsList.json?["items"] as? [[String: Any]]
        XCTAssertEqual(docsItems?.count, 1)
        XCTAssertEqual(docsItems?[0]["name"] as? String, "Invoices")
        let breadcrumbs = docsList.json?["path"] as? [[String: Any]]
        XCTAssertEqual(breadcrumbs?.count, 1)
        XCTAssertEqual(breadcrumbs?[0]["name"] as? String, "Documents")

        // 6. Rename Documents to Photos (conflict in root) -> 409
        let renameConflict = try req(
            path: "/api/nodes/\(docsId!)",
            method: "PATCH",
            jsonBody: ["name": "Photos"],
            cookie: cookie
        )
        XCTAssertEqual(renameConflict.status, 409)

        // 7. Move Documents into Invoices (cycle prevention) -> 400 invalid_move
        let moveCycle = try req(
            path: "/api/nodes/move",
            method: "POST",
            jsonBody: ["ids": [docsId!], "parentId": invoicesId!],
            cookie: cookie
        )
        XCTAssertEqual(moveCycle.status, 400)
        let moveErr = moveCycle.json?["error"] as? [String: Any]
        XCTAssertEqual(moveErr?["code"] as? String, "invalid_move")
    }

    func testTrashRestorePurge() throws {
        guard let s = server else { return }
        let l = try req(path: "/api/login", method: "POST", jsonBody: ["username": s.credentials.username, "password": s.credentials.password])
        let cookie = extractCookie(from: l.headers)!

        // Create folder to trash
        let f = try req(path: "/api/folders", method: "POST", jsonBody: ["name": "ToTrash"], cookie: cookie)
        let folderId = f.json?["id"] as! String

        // Trash
        let trashResp = try req(path: "/api/nodes/trash", method: "POST", jsonBody: ["ids": [folderId]], cookie: cookie)
        XCTAssertEqual(trashResp.status, 200)
        XCTAssertEqual(trashResp.json?["count"] as? Int, 1)

        // Not in active list
        let activeList = try req(path: "/api/nodes", cookie: cookie)
        let activeItems = activeList.json?["items"] as? [[String: Any]]
        XCTAssertEqual(activeItems?.filter { ($0["id"] as? String) == folderId }.count, 0)

        // Present in trash list
        let trashList = try req(path: "/api/trash", cookie: cookie)
        let trashItems = trashList.json?["items"] as? [[String: Any]]
        XCTAssertEqual(trashItems?.filter { ($0["id"] as? String) == folderId }.count, 1)

        // Restore
        let restoreResp = try req(path: "/api/nodes/restore", method: "POST", jsonBody: ["ids": [folderId]], cookie: cookie)
        XCTAssertEqual(restoreResp.status, 200)

        // Trash again and purge
        _ = try req(path: "/api/nodes/trash", method: "POST", jsonBody: ["ids": [folderId]], cookie: cookie)
        let purgeResp = try req(path: "/api/nodes/purge", method: "POST", jsonBody: ["ids": [folderId]], cookie: cookie)
        XCTAssertEqual(purgeResp.status, 200)
        XCTAssertEqual(purgeResp.json?["count"] as? Int, 1)

        // Verify trash is empty
        let trashAfterPurge = try req(path: "/api/trash", cookie: cookie)
        let emptyItems = trashAfterPurge.json?["items"] as? [[String: Any]]
        XCTAssertEqual(emptyItems?.count, 0)
    }

    func testTagsCrudAndApply() throws {
        guard let s = server else { return }
        let l = try req(path: "/api/login", method: "POST", jsonBody: ["username": s.credentials.username, "password": s.credentials.password])
        let cookie = extractCookie(from: l.headers)!

        // 1. Create tag
        let createTag = try req(
            path: "/api/tags",
            method: "POST",
            jsonBody: ["name": "Work", "color": "#ff0000"],
            cookie: cookie
        )
        XCTAssertEqual(createTag.status, 201)
        let tagId = createTag.json?["id"] as! Int64

        // 2. Duplicate tag name -> 409
        let dupTag = try req(
            path: "/api/tags",
            method: "POST",
            jsonBody: ["name": "Work", "color": "#00ff00"],
            cookie: cookie
        )
        XCTAssertEqual(dupTag.status, 409)

        // 3. Invalid color format -> 400
        let badColor = try req(
            path: "/api/tags",
            method: "POST",
            jsonBody: ["name": "Personal", "color": "blue"],
            cookie: cookie
        )
        XCTAssertEqual(badColor.status, 400)

        // 4. Update tag
        let updateTag = try req(
            path: "/api/tags/\(tagId)",
            method: "PATCH",
            jsonBody: ["name": "Office", "color": "#00ff00"],
            cookie: cookie
        )
        XCTAssertEqual(updateTag.status, 200)
        XCTAssertEqual(updateTag.json?["name"] as? String, "Office")

        // 5. Apply tag to folder
        let folder = try req(path: "/api/folders", method: "POST", jsonBody: ["name": "TaggedFolder"], cookie: cookie)
        let folderId = folder.json?["id"] as! String

        let applyResp = try req(
            path: "/api/nodes/tag",
            method: "POST",
            jsonBody: ["ids": [folderId], "add": [tagId]],
            cookie: cookie
        )
        XCTAssertEqual(applyResp.status, 200)
        let taggedItems = applyResp.json?["items"] as? [[String: Any]]
        let assignedTags = taggedItems?[0]["tagIds"] as? [Int64]
        XCTAssertEqual(assignedTags, [tagId])

        // 6. Delete tag -> 204
        let delTag = try req(path: "/api/tags/\(tagId)", method: "DELETE", cookie: cookie)
        XCTAssertEqual(delTag.status, 204)
    }

    func testSearchAndStats() throws {
        guard let s = server else { return }
        let l = try req(path: "/api/login", method: "POST", jsonBody: ["username": s.credentials.username, "password": s.credentials.password])
        let cookie = extractCookie(from: l.headers)!

        _ = try req(path: "/api/folders", method: "POST", jsonBody: ["name": "AlphaProject"], cookie: cookie)
        _ = try req(path: "/api/folders", method: "POST", jsonBody: ["name": "BetaProject"], cookie: cookie)

        // Search by query q
        let search = try req(path: "/api/search?q=alph", cookie: cookie)
        XCTAssertEqual(search.status, 200)
        let results = search.json?["items"] as? [[String: Any]]
        XCTAssertEqual(results?.count, 1)
        XCTAssertEqual(results?[0]["name"] as? String, "AlphaProject")

        // Search with no params -> 400
        let badSearch = try req(path: "/api/search", cookie: cookie)
        XCTAssertEqual(badSearch.status, 400)

        // Stats
        let stats = try req(path: "/api/stats", cookie: cookie)
        XCTAssertEqual(stats.status, 200)
        XCTAssertGreaterThanOrEqual(stats.json?["folderCount"] as! Int, 2)
        XCTAssertNotNil(stats.json?["diskFree"])
        XCTAssertNotNil(stats.json?["ratio"])
    }

    func testMalformedJsonAndBodyTooLarge() throws {
        guard let s = server else { return }
        let l = try req(path: "/api/login", method: "POST", jsonBody: ["username": s.credentials.username, "password": s.credentials.password])
        let cookie = extractCookie(from: l.headers)!

        // Malformed JSON -> 400
        let badJson = try req(
            path: "/api/folders",
            method: "POST",
            rawBody: Data("{not valid json".utf8),
            cookie: cookie,
            customHeaders: ["Content-Type": "application/json"]
        )
        XCTAssertEqual(badJson.status, 400)

        // Body > 1MB -> 413
        let largeBody = Data([UInt8](repeating: 0x41, count: 1024 * 1024 + 100))
        let tooLarge = try req(
            path: "/api/folders",
            method: "POST",
            rawBody: largeBody,
            cookie: cookie,
            customHeaders: ["Content-Type": "application/json"]
        )
        XCTAssertEqual(tooLarge.status, 413)
    }
}
