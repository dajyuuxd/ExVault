// POSIX socket-based HTTP/1.1 server with keep-alive, streaming, and connection throttling.

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum SocketError: Error {
    case closed
    case timeout
}

final class SocketWriter: ResponseWriter {
    let fd: Int32
    private(set) var bytesWritten: Int64 = 0

    init(fd: Int32) {
        self.fd = fd
    }

    func write(_ ptr: UnsafeRawPointer, count: Int) throws {
        guard count > 0 else { return }
        do {
            try Net.writeFully(fd: fd, ptr, count: count)
            bytesWritten += Int64(count)
        } catch {
            throw SocketError.closed
        }
    }
}

final class ChunkedResponseWriter: ResponseWriter {
    let raw: ResponseWriter
    private(set) var bytesWritten: Int64 = 0

    init(raw: ResponseWriter) {
        self.raw = raw
    }

    func write(_ ptr: UnsafeRawPointer, count: Int) throws {
        guard count > 0 else { return }
        let header = String(count, radix: 16) + "\r\n"
        let headerData = Data(header.utf8)
        try raw.write(headerData)
        try raw.write(ptr, count: count)
        let crlf = Data("\r\n".utf8)
        try raw.write(crlf)
        bytesWritten += Int64(count)
    }

    func finish() throws {
        let terminal = Data("0\r\n\r\n".utf8)
        try raw.write(terminal)
    }
}

public final class HttpServer {
    public let maxConnections: Int
    private let handler: (HttpRequest) -> HttpResponse

    private var listenFd: Int32 = -1
    public private(set) var boundPort: UInt16 = 0
    private var isRunning: Bool = false
    private let stateLock = NSLock()

    private var acceptThread: Thread?
    private var connectionSemaphore: DispatchSemaphore?
    private let clientsLock = NSLock()
    private var activeClients: Set<Int32> = []

    public init(maxConnections: Int = 8, handler: @escaping (HttpRequest) -> HttpResponse) {
        self.maxConnections = maxConnections
        self.handler = handler
    }

    deinit {
        stop()
    }

    @discardableResult
    public func start(port: UInt16 = 8080) throws -> UInt16 {
        stateLock.lock()
        defer { stateLock.unlock() }

        if isRunning {
            return boundPort
        }

        signal(SIGPIPE, SIG_IGN)

        if port == 0 {
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            if fd < 0 {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            var opt: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))

            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = 0
            addr.sin_addr.s_addr = in_addr_t(0) // INADDR_ANY

            let bindRes = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if bindRes < 0 {
                let err = errno
                close(fd)
                throw POSIXError(POSIXErrorCode(rawValue: err) ?? .EADDRINUSE)
            }

            if listen(fd, 16) < 0 {
                let err = errno
                close(fd)
                throw POSIXError(POSIXErrorCode(rawValue: err) ?? .EIO)
            }

            var actualAddr = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let sockNameRes = withUnsafeMutablePointer(to: &actualAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    getsockname(fd, sa, &len)
                }
            }
            if sockNameRes < 0 {
                let err = errno
                close(fd)
                throw POSIXError(POSIXErrorCode(rawValue: err) ?? .EIO)
            }

            self.listenFd = fd
            self.boundPort = UInt16(bigEndian: actualAddr.sin_port)
        } else {
            var bound = false
            let maxPort = port <= 65525 ? port + 10 : 65535
            for tryPort in port...maxPort {
                let fd = socket(AF_INET, SOCK_STREAM, 0)
                if fd < 0 {
                    continue
                }
                var opt: Int32 = 1
                setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))

                var addr = sockaddr_in()
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = tryPort.bigEndian
                addr.sin_addr.s_addr = in_addr_t(0) // INADDR_ANY

                let bindRes = withUnsafePointer(to: &addr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
                if bindRes == 0 {
                    if listen(fd, 16) == 0 {
                        self.listenFd = fd
                        self.boundPort = tryPort
                        bound = true
                        break
                    }
                }
                close(fd)
            }
            if !bound {
                throw POSIXError(.EADDRINUSE)
            }
        }

        self.isRunning = true
        self.connectionSemaphore = DispatchSemaphore(value: maxConnections)

        let thread = Thread { [weak self] in
            self?.acceptLoop()
        }
        thread.name = "exv.http.accept"
        self.acceptThread = thread
        thread.start()

        return self.boundPort
    }

    public func stop() {
        stateLock.lock()
        if !isRunning {
            stateLock.unlock()
            return
        }
        isRunning = false
        let fd = listenFd
        listenFd = -1
        boundPort = 0
        stateLock.unlock()

        if fd >= 0 {
            shutdown(fd, SHUT_RDWR)
            close(fd)
        }

        clientsLock.lock()
        for clientFd in activeClients {
            shutdown(clientFd, SHUT_RDWR)
            close(clientFd)
        }
        activeClients.removeAll()
        clientsLock.unlock()

        acceptThread?.cancel()
        acceptThread = nil
    }

    private func acceptLoop() {
        while true {
            stateLock.lock()
            let running = self.isRunning
            let serverFd = self.listenFd
            stateLock.unlock()

            guard running && serverFd >= 0 else { break }

            var clientAddr = sockaddr_in()
            var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let clientFd = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    accept(serverFd, sa, &addrLen)
                }
            }

            if clientFd < 0 {
                stateLock.lock()
                let stillRunning = self.isRunning
                stateLock.unlock()
                if !stillRunning { break }
                let err = errno
                if err == EINTR { continue }
                if err == EBADF || err == EINVAL { break }
                continue
            }

            var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &clientAddr.sin_addr, &ipBuf, socklen_t(INET_ADDRSTRLEN))
            let remoteIP = String(cString: ipBuf)

            guard let sem = self.connectionSemaphore else {
                close(clientFd)
                break
            }

            if sem.wait(timeout: .now()) == .timedOut {
                // Connection cap exceeded: reply 503 busy immediately and close
                send503Busy(fd: clientFd)
                close(clientFd)
                continue
            }

            clientsLock.lock()
            activeClients.insert(clientFd)
            clientsLock.unlock()

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                defer {
                    self?.clientsLock.lock()
                    self?.activeClients.remove(clientFd)
                    self?.clientsLock.unlock()
                    close(clientFd)
                    sem.signal()
                }
                self?.handleClient(fd: clientFd, remoteIP: remoteIP)
            }
        }
    }

    private func handleClient(fd: Int32, remoteIP: String) {
        #if canImport(Darwin)
        var nosigpipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))
        #endif

        var nodelay: Int32 = 1
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &nodelay, socklen_t(MemoryLayout<Int32>.size))

        let bufSize = 64 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buffer.deallocate() }

        var requestCount = 0

        while true {
            stateLock.lock()
            let running = self.isRunning
            stateLock.unlock()
            if !running { break }

            requestCount += 1
            setSocketTimeout(fd: fd, seconds: requestCount == 1 ? 30 : 15)

            var bytesInBuffer = 0
            var headerEndIndex: Int? = nil

            while bytesInBuffer < bufSize {
                let n = read(fd, buffer.advanced(by: bytesInBuffer), bufSize - bytesInBuffer)
                if n <= 0 {
                    return // Client closed or timeout
                }
                let prevCount = bytesInBuffer
                bytesInBuffer += n

                let searchStart = max(0, prevCount - 3)
                for i in searchStart..<(bytesInBuffer - 3) {
                    if buffer[i] == 0x0D && buffer[i + 1] == 0x0A &&
                       buffer[i + 2] == 0x0D && buffer[i + 3] == 0x0A {
                        headerEndIndex = i + 4
                        break
                    }
                }
                if let end = headerEndIndex {
                    if end > 16 * 1024 {
                        sendSimpleResponse(fd: fd, status: 431, body: "{\"error\":{\"code\":\"header_too_large\",\"message\":\"Header exceeds 16KB\"}}")
                        return
                    }
                    break
                }
                if bytesInBuffer >= 16 * 1024 {
                    sendSimpleResponse(fd: fd, status: 431, body: "{\"error\":{\"code\":\"header_too_large\",\"message\":\"Header exceeds 16KB\"}}")
                    return
                }
            }

            guard let endOfHeader = headerEndIndex else {
                sendSimpleResponse(fd: fd, status: 431, body: "{\"error\":{\"code\":\"header_too_large\",\"message\":\"Header too large\"}}")
                return
            }

            if endOfHeader > 16 * 1024 {
                sendSimpleResponse(fd: fd, status: 431, body: "{\"error\":{\"code\":\"header_too_large\",\"message\":\"Header exceeds 16KB\"}}")
                return
            }

            guard let headerString = String(bytes: UnsafeRawBufferPointer(start: buffer, count: endOfHeader), encoding: .utf8) ??
                                     String(bytes: UnsafeRawBufferPointer(start: buffer, count: endOfHeader), encoding: .isoLatin1) else {
                sendSimpleResponse(fd: fd, status: 400, body: "{\"error\":{\"code\":\"bad_request\",\"message\":\"Malformed header bytes\"}}")
                return
            }

            let lines = headerString.components(separatedBy: "\r\n")
            if lines.isEmpty || lines[0].isEmpty {
                sendSimpleResponse(fd: fd, status: 400, body: "{\"error\":{\"code\":\"bad_request\",\"message\":\"Empty request line\"}}")
                return
            }

            // Reject obs-fold (header line starting with space or tab)
            for i in 1..<lines.count {
                let line = lines[i]
                if line.hasPrefix(" ") || line.hasPrefix("\t") {
                    sendSimpleResponse(fd: fd, status: 400, body: "{\"error\":{\"code\":\"bad_request\",\"message\":\"Obs-fold headers are not supported\"}}")
                    return
                }
            }

            // Budget requirement: max 64 headers
            let headerLines = lines.dropFirst().filter { !$0.isEmpty }
            if headerLines.count > 64 {
                sendSimpleResponse(fd: fd, status: 431, body: "{\"error\":{\"code\":\"header_too_large\",\"message\":\"Too many headers (>64)\"}}")
                return
            }

            let reqLineParts = lines[0].split(separator: " ", omittingEmptySubsequences: true)
            guard reqLineParts.count >= 2 else {
                sendSimpleResponse(fd: fd, status: 400, body: "{\"error\":{\"code\":\"bad_request\",\"message\":\"Malformed request line\"}}")
                return
            }

            let method = String(reqLineParts[0]).uppercased()
            let rawTarget = String(reqLineParts[1])
            let version = reqLineParts.count >= 3 ? String(reqLineParts[2]).uppercased() : "HTTP/1.1"

            let supportedMethods: Set<String> = ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE"]
            if !supportedMethods.contains(method) {
                sendSimpleResponse(
                    fd: fd,
                    status: 405,
                    body: "{\"error\":{\"code\":\"method_not_allowed\",\"message\":\"Method not allowed\"}}",
                    extraHeaders: [("Allow", "GET, HEAD, POST, PUT, PATCH, DELETE")]
                )
                return
            }

            let isHttp10 = (version == "HTTP/1.0")

            let targetParts = rawTarget.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            let rawPath = String(targetParts[0])
            let rawQuery = targetParts.count > 1 ? String(targetParts[1]) : ""

            guard let decodedPath = Net.percentDecode(rawPath) else {
                sendSimpleResponse(fd: fd, status: 400, body: "{\"error\":{\"code\":\"bad_request\",\"message\":\"Invalid URL percent encoding\"}}")
                return
            }

            let query = Net.parseQuery(rawQuery)

            var headers: [String: String] = [:]
            for line in headerLines {
                guard let colonIdx = line.firstIndex(of: ":") else {
                    sendSimpleResponse(fd: fd, status: 400, body: "{\"error\":{\"code\":\"bad_request\",\"message\":\"Invalid header syntax\"}}")
                    return
                }
                let k = line[..<colonIdx].trimmingCharacters(in: .whitespaces).lowercased()
                let v = line[line.index(after: colonIdx)...].trimmingCharacters(in: .whitespaces)
                headers[k] = v
            }

            if let te = headers["transfer-encoding"], te.lowercased().contains("chunked") {
                sendSimpleResponse(fd: fd, status: 411, body: "{\"error\":{\"code\":\"length_required\",\"message\":\"Client chunked transfer encoding is not supported\"}}")
                return
            }

            var contentLength: Int64 = 0
            if let clStr = headers["content-length"] {
                guard let cl = Int64(clStr), cl >= 0 else {
                    sendSimpleResponse(fd: fd, status: 400, body: "{\"error\":{\"code\":\"bad_request\",\"message\":\"Invalid Content-Length\"}}")
                    return
                }
                contentLength = cl
            }

            var cookies: [String: String] = [:]
            if let cookieHeader = headers["cookie"] {
                let pairs = cookieHeader.split(separator: ";")
                for pair in pairs {
                    let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    if parts.count == 2 {
                        let ck = parts[0].trimmingCharacters(in: .whitespaces)
                        let cv = parts[1].trimmingCharacters(in: .whitespaces)
                        cookies[ck] = cv
                    }
                }
            }

            let leftoverCount = bytesInBuffer - endOfHeader
            var initialBytes: [UInt8] = []
            if leftoverCount > 0 {
                initialBytes = [UInt8](repeating: 0, count: leftoverCount)
                initialBytes.withUnsafeMutableBytes { raw in
                    guard let base = raw.baseAddress else { return }
                    base.copyMemory(from: buffer.advanced(by: endOfHeader), byteCount: leftoverCount)
                }
            }

            let bodyReader = BodyReader(contentLength: contentLength, initialData: initialBytes) { outBuf, maxBytes in
                let n = read(fd, outBuf, maxBytes)
                if n < 0 {
                    let err = errno
                    if err == EINTR {
                        let retryN = read(fd, outBuf, maxBytes)
                        if retryN >= 0 { return retryN }
                    }
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                return n
            }

            let request = HttpRequest(
                method: method,
                path: decodedPath,
                query: query,
                headers: headers,
                cookies: cookies,
                remoteIP: remoteIP,
                body: bodyReader
            )

            let clientConn = headers["connection"]?.lowercased()
            let clientKeepAlive: Bool = isHttp10 ? (clientConn == "keep-alive") : (clientConn != "close")

            let response = handler(request)

            var responseHeaders = response.headers
            let userConn = responseHeaders.first { $0.0.caseInsensitiveCompare("connection") == .orderedSame }?.1
            let shouldClose = (userConn?.lowercased() == "close") || !clientKeepAlive || bodyReader.shouldCloseConnection

            responseHeaders.removeAll {
                $0.0.caseInsensitiveCompare("server") == .orderedSame ||
                $0.0.caseInsensitiveCompare("connection") == .orderedSame
            }
            responseHeaders.append(("Server", "ExVault"))
            responseHeaders.append(("Connection", shouldClose ? "close" : "keep-alive"))

            switch response.body {
            case .none:
                if response.status != 204 && response.status != 304 && method != "HEAD" {
                    if !responseHeaders.contains(where: { $0.0.caseInsensitiveCompare("content-length") == .orderedSame }) {
                        responseHeaders.append(("Content-Length", "0"))
                    }
                }
            case .data(let data):
                responseHeaders.removeAll { $0.0.caseInsensitiveCompare("content-length") == .orderedSame }
                responseHeaders.append(("Content-Length", "\(data.count)"))
            case .stream(let length, _):
                if let length = length {
                    responseHeaders.removeAll { $0.0.caseInsensitiveCompare("content-length") == .orderedSame }
                    responseHeaders.append(("Content-Length", "\(length)"))
                } else {
                    responseHeaders.removeAll { $0.0.caseInsensitiveCompare("transfer-encoding") == .orderedSame }
                    responseHeaders.append(("Transfer-Encoding", "chunked"))
                }
            }

            var headerText = "HTTP/1.1 \(response.status) \(HttpStatus.text(for: response.status))\r\n"
            for (k, v) in responseHeaders {
                headerText += "\(k): \(v)\r\n"
            }
            headerText += "\r\n"

            do {
                let headerData = Data(headerText.utf8)
                try headerData.withUnsafeBytes { raw in
                    guard let base = raw.baseAddress else { return }
                    try Net.writeFully(fd: fd, base, count: headerData.count)
                }

                if method != "HEAD" {
                    switch response.body {
                    case .none:
                        break
                    case .data(let data):
                        try data.withUnsafeBytes { raw in
                            guard let base = raw.baseAddress else { return }
                            try Net.writeFully(fd: fd, base, count: data.count)
                        }
                    case .stream(let length, let writer):
                        let socketWriter = SocketWriter(fd: fd)
                        if length != nil {
                            try writer(socketWriter)
                        } else {
                            let chunked = ChunkedResponseWriter(raw: socketWriter)
                            try writer(chunked)
                            try chunked.finish()
                        }
                    }
                }
            } catch {
                // Client closed socket or write error -> exit
                return
            }

            do {
                try bodyReader.discardRemaining()
            } catch {
                return
            }

            if shouldClose || bodyReader.shouldCloseConnection {
                return
            }
        }
    }

    private func send503Busy(fd: Int32) {
        sendSimpleResponse(
            fd: fd,
            status: 503,
            body: "{\"error\":{\"code\":\"busy\",\"message\":\"Server is busy\"}}"
        )
    }

    private func sendSimpleResponse(
        fd: Int32,
        status: Int,
        body: String,
        extraHeaders: [(String, String)] = []
    ) {
        let bodyData = Data(body.utf8)
        var headerStr = "HTTP/1.1 \(status) \(HttpStatus.text(for: status))\r\n"
        headerStr += "Server: ExVault\r\n"
        headerStr += "Connection: close\r\n"
        headerStr += "Content-Type: application/json; charset=utf-8\r\n"
        headerStr += "Content-Length: \(bodyData.count)\r\n"
        for (k, v) in extraHeaders {
            headerStr += "\(k): \(v)\r\n"
        }
        headerStr += "\r\n"

        let headerData = Data(headerStr.utf8)
        try? headerData.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            try? Net.writeFully(fd: fd, base, count: headerData.count)
        }
        try? bodyData.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            try? Net.writeFully(fd: fd, base, count: bodyData.count)
        }
    }

    private func setSocketTimeout(fd: Int32, seconds: Int) {
        var tv = timeval()
        tv.tv_sec = seconds
        tv.tv_usec = 0
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }
}
