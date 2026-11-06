// Authentication and system endpoints: health, login, logout, me, and heartbeat ping.

import Foundation

public enum AuthApi: ApiModule {
    private struct LoginRequest: Decodable {
        let username: String
        let password: String
    }

    public static func register(_ r: Router, _ ctx: ApiContext) {
        // GET /api/health
        r.add("GET", "/api/health", auth: false) { _ in
            return HttpResponse.jsonRaw(["ok": true, "version": ExVaultInfo.version])
        }

        // POST /api/ping & GET /api/ping (Heartbeat)
        r.add("POST", "/api/ping", auth: true) { _ in
            return HttpResponse(status: 204, headers: [], body: .none)
        }
        r.add("GET", "/api/ping", auth: true) { _ in
            return HttpResponse(status: 204, headers: [], body: .none)
        }

        // POST /api/login
        r.add("POST", "/api/login", auth: false) { req in
            if let waitSecs = ctx.limiter.allowed(ip: req.remoteIP) {
                let retryAfter = String(Int(ceil(waitSecs)))
                Log.warn("Auth: Rate limited IP \(req.remoteIP), retry after \(retryAfter)s")
                return HttpResponse(
                    status: 429,
                    headers: [
                        ("Retry-After", retryAfter),
                        ("Content-Type", "application/json; charset=utf-8")
                    ],
                    body: .data(Data("{\"error\":{\"code\":\"rate_limited\",\"message\":\"Too many failed login attempts. Please wait.\"}}".utf8))
                )
            }

            let loginReq = try ctx.json(req, LoginRequest.self)
            let userMatch = Net.constantTimeEquals(loginReq.username, ctx.credentials.username)
            let passMatch = Net.constantTimeEquals(loginReq.password, ctx.credentials.password)

            guard userMatch && passMatch else {
                ctx.limiter.recordFailure(ip: req.remoteIP)
                Log.warn("Auth: Login failed for user '\(loginReq.username)' from \(req.remoteIP)")
                return HttpResponse.error(ApiError.unauthorized("Invalid username or password", code: "bad_credentials"))
            }

            ctx.limiter.recordSuccess(ip: req.remoteIP)
            let token = ctx.sessions.create()
            let cookie = "exv_sid=\(token); Path=/; HttpOnly; SameSite=Strict; Max-Age=604800"
            Log.info("Auth: Login success for '\(loginReq.username)' from \(req.remoteIP)")

            return HttpResponse(
                status: 204,
                headers: [("Set-Cookie", cookie)],
                body: .none
            )
        }

        // POST /api/logout
        r.add("POST", "/api/logout", auth: false) { req in
            let token = req.cookies["exv_sid"]
            ctx.sessions.destroy(token)
            let cookie = "exv_sid=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0"
            return HttpResponse(
                status: 204,
                headers: [("Set-Cookie", cookie)],
                body: .none
            )
        }

        // GET /api/me
        r.add("GET", "/api/me", auth: true) { _ in
            let payload: [String: Any] = [
                "username": ctx.credentials.username,
                "chunkSize": ctx.config.uploadChunkSize,
                "limits": [
                    "maxZipBytes": 4294967295 as Int64
                ]
            ]
            return HttpResponse.jsonRaw(payload)
        }
    }
}
