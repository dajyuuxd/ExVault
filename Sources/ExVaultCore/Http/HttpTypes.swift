// HTTP types: Request, BodyReader, Response, ResponseWriter, and ApiError.

import Foundation

public struct HttpRequest {
    public let method: String
    public let path: String
    public let query: [String: String]
    public let headers: [String: String]
    public let cookies: [String: String]
    public let remoteIP: String
    public let body: BodyReader
    public var params: [String: String]

    public init(
        method: String,
        path: String,
        query: [String: String] = [:],
        headers: [String: String] = [:],
        cookies: [String: String] = [:],
        remoteIP: String = "127.0.0.1",
        body: BodyReader,
        params: [String: String] = [:]
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
        self.cookies = cookies
        self.remoteIP = remoteIP
        self.body = body
        self.params = params
    }
}

public final class BodyReader {
    public let contentLength: Int64
    public private(set) var remaining: Int64
    public private(set) var shouldCloseConnection: Bool = false

    private var initialBuffer: [UInt8]
    private var initialOffset: Int = 0
    private let readNextChunk: (UnsafeMutableRawPointer, Int) throws -> Int

    public init(
        contentLength: Int64,
        initialData: [UInt8] = [],
        readNext: @escaping (UnsafeMutableRawPointer, Int) throws -> Int
    ) {
        self.contentLength = contentLength
        self.remaining = contentLength
        self.initialBuffer = initialData
        self.readNextChunk = readNext
    }

    /// Reads up to max bytes into buf. Returns bytes read (0 when no more body).
    public func read(into buf: UnsafeMutableRawPointer, max: Int) throws -> Int {
        guard remaining > 0 && max > 0 else { return 0 }

        if initialOffset < initialBuffer.count {
            let available = initialBuffer.count - initialOffset
            let toCopy = Swift.min(max, Swift.min(available, Int(remaining)))
            initialBuffer.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                buf.copyMemory(from: base.advanced(by: initialOffset), byteCount: toCopy)
            }
            initialOffset += toCopy
            remaining -= Int64(toCopy)
            return toCopy
        }

        let toRead = Swift.min(max, Int(Swift.min(Int64(max), remaining)))
        let n = try readNextChunk(buf, toRead)
        if n <= 0 {
            remaining = 0
            return 0
        }
        remaining -= Int64(n)
        return n
    }

    /// Reads all body data up to limit. Throws ApiError.payloadTooLarge if exceeded.
    public func readAll(limit: Int = 1024 * 1024) throws -> Data {
        if contentLength > Int64(limit) {
            throw ApiError.payloadTooLarge("Request body exceeds \(limit) bytes")
        }
        var result = Data()
        if contentLength > 0 {
            result.reserveCapacity(Int(contentLength))
        }
        let bufSize = 64 * 1024
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buf.deallocate() }

        while remaining > 0 {
            let toRead = Swift.min(bufSize, Int(remaining))
            let n = try read(into: buf, max: toRead)
            if n <= 0 { break }
            if result.count + n > limit {
                throw ApiError.payloadTooLarge("Request body exceeds \(limit) bytes")
            }
            result.append(buf, count: n)
        }
        return result
    }

    /// Discards any remaining unread body bytes. If remaining > 8MB, marks connection to close.
    public func discardRemaining() throws {
        guard remaining > 0 else { return }
        if remaining > 8 * 1024 * 1024 {
            shouldCloseConnection = true
            return
        }
        let bufSize = 64 * 1024
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buf.deallocate() }

        while remaining > 0 {
            let toRead = Swift.min(bufSize, Int(remaining))
            let n = try read(into: buf, max: toRead)
            if n <= 0 {
                shouldCloseConnection = true
                break
            }
        }
    }
}

public protocol ResponseWriter {
    func write(_ ptr: UnsafeRawPointer, count: Int) throws
}

public extension ResponseWriter {
    func write(_ data: Data) throws {
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            try write(base, count: data.count)
        }
    }
}

public enum ResponseBody {
    case none
    case data(Data)
    case stream(length: Int64?, writer: (ResponseWriter) throws -> Void)
}

public struct HttpResponse {
    public var status: Int
    public var headers: [(String, String)]
    public var body: ResponseBody

    public init(status: Int, headers: [(String, String)] = [], body: ResponseBody = .none) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    public static func json<T: Encodable>(_ obj: T, status: Int = 200) -> HttpResponse {
        do {
            let data = try JSONEncoder().encode(obj)
            return HttpResponse(
                status: status,
                headers: [("Content-Type", "application/json; charset=utf-8")],
                body: .data(data)
            )
        } catch {
            return HttpResponse.error(ApiError.internalError("JSON encode error: \(error)"))
        }
    }

    public static func jsonRaw(_ dict: [String: Any], status: Int = 200) -> HttpResponse {
        do {
            let data = try JSONSerialization.data(withJSONObject: dict, options: [])
            return HttpResponse(
                status: status,
                headers: [("Content-Type", "application/json; charset=utf-8")],
                body: .data(data)
            )
        } catch {
            return HttpResponse.error(ApiError.internalError("JSON serialization error: \(error)"))
        }
    }

    public static func error(_ err: ApiError) -> HttpResponse {
        var errDict: [String: Any] = [
            "code": err.code,
            "message": err.message
        ]
        if let extra = err.extra {
            for (k, v) in extra {
                errDict[k] = v
            }
        }
        let dict: [String: Any] = ["error": errDict]
        let data = (try? JSONSerialization.data(withJSONObject: dict, options: []))
            ?? Data("{\"error\":{\"code\":\"error\",\"message\":\"Unknown error\"}}".utf8)
        return HttpResponse(
            status: err.status,
            headers: [("Content-Type", "application/json; charset=utf-8")],
            body: .data(data)
        )
    }

    public static func empty(_ status: Int) -> HttpResponse {
        return HttpResponse(status: status, headers: [], body: .none)
    }
}

public struct ApiError: Error, CustomStringConvertible {
    public let status: Int
    public let code: String
    public let message: String
    public var extra: [String: Any]?

    public init(status: Int, code: String, message: String, extra: [String: Any]? = nil) {
        self.status = status
        self.code = code
        self.message = message
        self.extra = extra
    }

    public var description: String {
        return "ApiError(\(status) \(code): \(message))"
    }

    public static func badRequest(_ m: String = "bad request", code: String = "bad_request") -> ApiError {
        return ApiError(status: 400, code: code, message: m)
    }

    public static func unauthorized(_ m: String = "unauthorized", code: String = "unauthorized") -> ApiError {
        return ApiError(status: 401, code: code, message: m)
    }

    public static func forbidden(_ m: String = "forbidden", code: String = "forbidden") -> ApiError {
        return ApiError(status: 403, code: code, message: m)
    }

    public static func notFound(_ m: String = "not found", code: String = "not_found") -> ApiError {
        return ApiError(status: 404, code: code, message: m)
    }

    public static func methodNotAllowed(_ m: String = "method not allowed", code: String = "method_not_allowed") -> ApiError {
        return ApiError(status: 405, code: code, message: m)
    }

    public static func conflict(_ m: String = "conflict", code: String = "conflict") -> ApiError {
        return ApiError(status: 409, code: code, message: m)
    }

    public static func lengthRequired(_ m: String = "length required", code: String = "length_required") -> ApiError {
        return ApiError(status: 411, code: code, message: m)
    }

    public static func payloadTooLarge(_ m: String = "payload too large", code: String = "payload_too_large") -> ApiError {
        return ApiError(status: 413, code: code, message: m)
    }

    public static func rangeNotSatisfiable(_ m: String = "range not satisfiable", code: String = "range_not_satisfiable") -> ApiError {
        return ApiError(status: 416, code: code, message: m)
    }

    public static func tooManyRequests(_ m: String = "too many requests", code: String = "too_many_requests") -> ApiError {
        return ApiError(status: 429, code: code, message: m)
    }

    public static func headerFieldsTooLarge(_ m: String = "request header fields too large", code: String = "header_fields_too_large") -> ApiError {
        return ApiError(status: 431, code: code, message: m)
    }

    public static func internalError(_ m: String = "internal server error", code: String = "internal_error") -> ApiError {
        return ApiError(status: 500, code: code, message: m)
    }

    public static func serviceUnavailable(_ m: String = "service unavailable", code: String = "service_unavailable") -> ApiError {
        return ApiError(status: 503, code: code, message: m)
    }

    public static func insufficientStorage(_ m: String = "insufficient storage", code: String = "insufficient_storage") -> ApiError {
        return ApiError(status: 507, code: code, message: m)
    }
}

public enum HttpStatus {
    public static func text(for code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 201: return "Created"
        case 202: return "Accepted"
        case 204: return "No Content"
        case 206: return "Partial Content"
        case 304: return "Not Modified"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 409: return "Conflict"
        case 411: return "Length Required"
        case 413: return "Payload Too Large"
        case 416: return "Range Not Satisfiable"
        case 429: return "Too Many Requests"
        case 431: return "Request Header Fields Too Large"
        case 500: return "Internal Server Error"
        case 503: return "Service Unavailable"
        case 507: return "Insufficient Storage"
        default: return "Status \(code)"
        }
    }
}
