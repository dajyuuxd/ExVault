// Static file server with path traversal protection, symlink escape checks, ETag caching, and streaming.

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct StaticFiles {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// Resolves a requested URL path to an absolute filesystem path safely inside `root`.
    /// Returns nil if path traverses outside root, contains null bytes or '..', or is not a regular file.
    public func resolve(urlPath: String) -> String? {
        guard !urlPath.isEmpty && urlPath.hasPrefix("/") else {
            return nil
        }

        if urlPath.contains("\0") {
            return nil
        }

        let targetPath = (urlPath == "/") ? "/index.html" : urlPath

        // Reject any traversal component
        let segments = targetPath.split(separator: "/", omittingEmptySubsequences: true)
        for seg in segments {
            if seg == ".." || seg == "." {
                return nil
            }
        }

        let combined = root.appendingPathComponent(segments.joined(separator: "/")).path

        guard let canonicalRoot = canonicalPath(for: root.path),
              let canonicalTarget = canonicalPath(for: combined) else {
            return nil
        }

        // Canonical root prefix check
        let rootPrefix = canonicalRoot.hasSuffix("/") ? canonicalRoot : canonicalRoot + "/"
        guard canonicalTarget.hasPrefix(rootPrefix) else {
            return nil
        }

        // Verify it is a regular file
        var statBuf = stat()
        if stat(canonicalTarget, &statBuf) != 0 {
            return nil
        }

        #if canImport(Darwin)
        let isRegular = (statBuf.st_mode & S_IFMT) == S_IFREG
        #elseif canImport(Glibc)
        let isRegular = (statBuf.st_mode & S_IFMT) == S_IFREG
        #else
        let isRegular = true
        #endif

        guard isRegular else {
            return nil
        }

        return canonicalTarget
    }

    public func serve(urlPath: String, ifNoneMatch: String?) -> HttpResponse {
        guard let resolvedPath = resolve(urlPath: urlPath) else {
            return HttpResponse.error(ApiError.notFound("File not found"))
        }

        var statBuf = stat()
        guard stat(resolvedPath, &statBuf) == 0 else {
            return HttpResponse.error(ApiError.notFound("File not found"))
        }

        let size = Int64(statBuf.st_size)
        #if canImport(Darwin)
        let mtime = statBuf.st_mtimespec.tv_sec
        #elseif canImport(Glibc)
        let mtime = statBuf.st_mtim.tv_sec
        #else
        let mtime = statBuf.st_mtime
        #endif

        let etag = "\"\(mtime)-\(size)\""

        if let inm = ifNoneMatch?.trimmingCharacters(in: .whitespaces), inm == etag {
            return HttpResponse(
                status: 304,
                headers: [
                    ("ETag", etag),
                    ("Cache-Control", "no-cache")
                ],
                body: .none
            )
        }

        let contentType = MimeTypes.contentType(forName: resolvedPath)

        return HttpResponse(
            status: 200,
            headers: [
                ("Content-Type", contentType),
                ("ETag", etag),
                ("Cache-Control", "no-cache")
            ],
            body: .stream(length: size) { writer in
                let fd = open(resolvedPath, O_RDONLY, 0)
                guard fd >= 0 else {
                    throw SocketError.closed
                }
                defer { close(fd) }

                let bufSize = 64 * 1024
                let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
                defer { buf.deallocate() }

                var remaining = size
                while remaining > 0 {
                    let toRead = min(bufSize, Int(remaining))
                    let n = read(fd, buf, toRead)
                    if n <= 0 { break }
                    try writer.write(buf, count: n)
                    remaining -= Int64(n)
                }
            }
        )
    }

    private func canonicalPath(for path: String) -> String? {
        #if canImport(Darwin) || canImport(Glibc)
        guard let real = realpath(path, nil) else { return nil }
        defer { free(real) }
        return String(cString: real)
        #else
        return (try? URL(fileURLWithPath: path).resolvingSymlinksInPath().path)
            ?? URL(fileURLWithPath: path).standardized.path
        #endif
    }
}
