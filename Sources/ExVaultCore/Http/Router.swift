// URL pattern-matching router with parameter binding, authentication checks, and error mapping.

import Foundation

public final class Router {
    public typealias Handler = (inout HttpRequest) throws -> HttpResponse

    private struct RouteEntry {
        let method: String
        let segments: [String]
        let isWildcard: Bool
        let auth: Bool
        let handler: Handler
    }

    private var routes: [RouteEntry] = []
    private let lock = NSLock()

    public var routeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return routes.count
    }

    public init() {}

    public func add(_ method: String, _ pattern: String, auth: Bool = true, _ handler: @escaping Handler) {
        lock.lock()
        defer { lock.unlock() }

        var rawSegments = pattern.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let isWildcard = rawSegments.last == "*"
        if isWildcard {
            rawSegments.removeLast()
        }

        routes.append(RouteEntry(
            method: method.uppercased(),
            segments: rawSegments,
            isWildcard: isWildcard,
            auth: auth,
            handler: handler
        ))
    }

    public func dispatch(_ req: HttpRequest, authCheck: (HttpRequest) -> Bool) -> HttpResponse {
        var mutableReq = req
        let reqSegments = req.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        lock.lock()
        let allRoutes = self.routes
        lock.unlock()

        var matchingRoutes: [RouteEntry] = []
        var matchedParams: [String: String] = [:]

        for route in allRoutes {
            if route.isWildcard {
                if reqSegments.count < route.segments.count {
                    continue
                }
            } else {
                if reqSegments.count != route.segments.count {
                    continue
                }
            }

            var matches = true
            var params: [String: String] = [:]
            for i in 0..<route.segments.count {
                let rSeg = route.segments[i]
                let reqSeg = reqSegments[i]
                if rSeg.hasPrefix(":") {
                    let key = String(rSeg.dropFirst())
                    params[key] = reqSeg
                } else if rSeg != reqSeg {
                    matches = false
                    break
                }
            }

            if matches {
                matchingRoutes.append(route)
                if matchedParams.isEmpty {
                    matchedParams = params
                }
            }
        }

        if matchingRoutes.isEmpty {
            return HttpResponse.error(ApiError.notFound("Route not found"))
        }

        guard let targetRoute = matchingRoutes.first(where: { $0.method == req.method })
            ?? (req.method == "HEAD" ? matchingRoutes.first(where: { $0.method == "GET" }) : nil) else {
            let allowedMethods = Array(Set(matchingRoutes.map { $0.method })).sorted().joined(separator: ", ")
            return HttpResponse(
                status: 405,
                headers: [
                    ("Allow", allowedMethods),
                    ("Content-Type", "application/json; charset=utf-8")
                ],
                body: .data(Data("{\"error\":{\"code\":\"method_not_allowed\",\"message\":\"Method not allowed\"}}".utf8))
            )
        }

        if targetRoute.auth && !authCheck(req) {
            return HttpResponse.error(ApiError.unauthorized("Unauthorized"))
        }

        mutableReq.params = matchedParams

        do {
            return try targetRoute.handler(&mutableReq)
        } catch let apiErr as ApiError {
            return HttpResponse.error(apiErr)
        } catch let storeErr as StoreError {
            return HttpResponse.error(ApiError.from(storeErr))
        } catch {
            Log.error("Unhandled route error: \(error)")
            return HttpResponse.error(ApiError.internalError(error.localizedDescription))
        }
    }
}
