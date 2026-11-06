// Unit tests for HTTP Router: route matching, path params, auth enforcement, and error mapping.

import XCTest
@testable import ExVaultCore

final class RouterTests: XCTestCase {

    private func makeRequest(method: String, path: String, authCookie: String? = nil) -> HttpRequest {
        var cookies: [String: String] = [:]
        if let cookie = authCookie {
            cookies["exv_sid"] = cookie
        }
        let reader = BodyReader(contentLength: 0) { _, _ in 0 }
        return HttpRequest(
            method: method,
            path: path,
            query: [:],
            headers: [:],
            cookies: cookies,
            remoteIP: "127.0.0.1",
            body: reader
        )
    }

    func testParamMatchingAndRouteCount() {
        let router = Router()
        XCTAssertEqual(router.routeCount, 0)

        router.add("GET", "/api/nodes/:id") { req in
            let id = req.params["id"] ?? "unknown"
            return HttpResponse.json(["nodeId": id])
        }
        XCTAssertEqual(router.routeCount, 1)

        let req = makeRequest(method: "GET", path: "/api/nodes/abc123456")
        let resp = router.dispatch(req) { _ in true }

        XCTAssertEqual(resp.status, 200)
        if case .data(let data) = resp.body {
            let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            XCTAssertEqual(json?["nodeId"] as? String, "abc123456")
        } else {
            XCTFail("Response body is not data")
        }
    }

    func testNotFound404() {
        let router = Router()
        router.add("GET", "/api/nodes") { _ in HttpResponse.empty(200) }

        let req = makeRequest(method: "GET", path: "/api/unknown")
        let resp = router.dispatch(req) { _ in true }

        XCTAssertEqual(resp.status, 404)
    }

    func testMethodNotAllowed405WithAllowHeader() {
        let router = Router()
        router.add("GET", "/api/nodes/:id") { _ in HttpResponse.empty(200) }
        router.add("PATCH", "/api/nodes/:id") { _ in HttpResponse.empty(200) }

        let req = makeRequest(method: "DELETE", path: "/api/nodes/123")
        let resp = router.dispatch(req) { _ in true }

        XCTAssertEqual(resp.status, 405)
        let allow = resp.headers.first { $0.0 == "Allow" }?.1
        XCTAssertNotNil(allow)
        XCTAssertTrue(allow?.contains("GET") == true)
        XCTAssertTrue(allow?.contains("PATCH") == true)
    }

    func testAuthEnforcement401() {
        let router = Router()
        router.add("GET", "/api/protected", auth: true) { _ in
            return HttpResponse.json(["secret": "data"])
        }
        router.add("GET", "/api/public", auth: false) { _ in
            return HttpResponse.json(["public": "info"])
        }

        let authChecker: (HttpRequest) -> Bool = { req in
            return req.cookies["exv_sid"] == "valid_token"
        }

        // Protected without auth -> 401
        let req1 = makeRequest(method: "GET", path: "/api/protected", authCookie: nil)
        let resp1 = router.dispatch(req1, authCheck: authChecker)
        XCTAssertEqual(resp1.status, 401)

        // Protected with valid auth -> 200
        let req2 = makeRequest(method: "GET", path: "/api/protected", authCookie: "valid_token")
        let resp2 = router.dispatch(req2, authCheck: authChecker)
        XCTAssertEqual(resp2.status, 200)

        // Public without auth -> 200
        let req3 = makeRequest(method: "GET", path: "/api/public", authCookie: nil)
        let resp3 = router.dispatch(req3, authCheck: authChecker)
        XCTAssertEqual(resp3.status, 200)
    }

    func testErrorMappingCatch() {
        let router = Router()

        // Throws ApiError
        router.add("GET", "/api/apierror") { _ in
            throw ApiError.badRequest("Missing parameters")
        }

        // Throws StoreError
        router.add("GET", "/api/storeerror") { _ in
            throw StoreError(code: "offset_mismatch", message: "Offset wrong", extra: ["offset": 500])
        }

        // Throws generic Error
        enum CustomError: Error {
            case unexpectedFailure
        }
        router.add("GET", "/api/genericerror") { _ in
            throw CustomError.unexpectedFailure
        }

        let req1 = makeRequest(method: "GET", path: "/api/apierror")
        let resp1 = router.dispatch(req1) { _ in true }
        XCTAssertEqual(resp1.status, 400)

        let req2 = makeRequest(method: "GET", path: "/api/storeerror")
        let resp2 = router.dispatch(req2) { _ in true }
        XCTAssertEqual(resp2.status, 409)
        if case .data(let data) = resp2.body {
            let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            let errObj = json?["error"] as? [String: Any]
            XCTAssertEqual(errObj?["code"] as? String, "offset_mismatch")
            XCTAssertEqual(errObj?["offset"] as? Int64, 500)
        } else {
            XCTFail("Response body not data")
        }

        let req3 = makeRequest(method: "GET", path: "/api/genericerror")
        let resp3 = router.dispatch(req3) { _ in true }
        XCTAssertEqual(resp3.status, 500)
    }
}
