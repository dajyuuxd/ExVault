// File content streaming (raw with Range, zlib raw DEFLATE) and thumbnail management.

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum FilesApi: ApiModule {

    public static func register(_ r: Router, _ ctx: ApiContext) {
        // GET /api/files/:id/content
        r.add("GET", "/api/files/:id/content", auth: true) { req in
            guard let id = req.params["id"],
                  let info = try ctx.store.fileBlobInfo(id) else {
                throw ApiError.notFound("File not found")
            }

            let blobPath = ctx.blobs.path(forBlob: info.blobId)
            let isAttachment = (req.query["dl"] == "1")
            let contentDisposition = formatContentDisposition(name: info.name, isAttachment: isAttachment)
            let contentType = formatContentType(mime: info.mime, name: info.name)
            let etag = "\"\(String(format: "%08x", info.crc32))-\(info.size)\""

            // 1. ETag caching check
            if let inm = req.headers["if-none-match"]?.trimmingCharacters(in: .whitespaces), inm == etag {
                return HttpResponse(
                    status: 304,
                    headers: [
                        ("ETag", etag),
                        ("Cache-Control", "private, no-cache")
                    ],
                    body: .none
                )
            }

            Log.info("Download: '\(info.name)' (\(info.size) B)")

            // 2. Codec: raw (0) vs zlib (1)
            if info.codec == 0 {
                let rangeResult = RangeParser.parse(header: req.headers["range"], size: info.size)
                switch rangeResult {
                case .none, .full:
                    var headers: [(String, String)] = [
                        ("Content-Type", contentType),
                        ("Content-Disposition", contentDisposition),
                        ("Content-Length", "\(info.size)"),
                        ("Accept-Ranges", "bytes"),
                        ("ETag", etag),
                        ("Cache-Control", "private, no-cache")
                    ]
                    return HttpResponse(
                        status: 200,
                        headers: headers,
                        body: .stream(length: info.size) { writer in
                            try streamRawRange(path: blobPath, start: 0, length: info.size, writer: writer)
                        }
                    )

                case .partial(let start, let end):
                    let length = end - start + 1
                    let headers: [(String, String)] = [
                        ("Content-Type", contentType),
                        ("Content-Disposition", contentDisposition),
                        ("Content-Range", "bytes \(start)-\(end)/\(info.size)"),
                        ("Content-Length", "\(length)"),
                        ("Accept-Ranges", "bytes"),
                        ("ETag", etag),
                        ("Cache-Control", "private, no-cache")
                    ]
                    return HttpResponse(
                        status: 206,
                        headers: headers,
                        body: .stream(length: length) { writer in
                            try streamRawRange(path: blobPath, start: start, length: length, writer: writer)
                        }
                    )

                case .invalid:
                    return HttpResponse(
                        status: 416,
                        headers: [
                            ("Content-Range", "bytes */\(info.size)"),
                            ("Content-Type", "application/json; charset=utf-8")
                        ],
                        body: .data(Data("{\"error\":{\"code\":\"range_not_satisfiable\",\"message\":\"Range not satisfiable\"}}".utf8))
                    )
                }
            } else {
                // Codec zlib raw DEFLATE: ignore Range, always full 200
                let headers: [(String, String)] = [
                    ("Content-Type", contentType),
                    ("Content-Disposition", contentDisposition),
                    ("Content-Length", "\(info.size)"),
                    ("Accept-Ranges", "none"),
                    ("ETag", etag),
                    ("Cache-Control", "private, no-cache")
                ]
                return HttpResponse(
                    status: 200,
                    headers: headers,
                    body: .stream(length: info.size) { writer in
                        let fd = open(blobPath, O_RDONLY, 0)
                        guard fd >= 0 else {
                            throw SocketError.closed
                        }
                        defer { close(fd) }

                        try Compressor.decompress(from: fd) { chunk in
                            try writer.write(chunk)
                        }
                    }
                )
            }
        }

        // GET /api/files/:id/thumb
        r.add("GET", "/api/files/:id/thumb", auth: true) { req in
            guard let id = req.params["id"],
                  let node = try ctx.store.getNode(id),
                  node.trashedAt == nil && node.hasThumb else {
                throw ApiError.notFound("Thumbnail not found")
            }

            let thumbPath = ctx.blobs.thumbPath(forNode: id)
            guard let fileHandle = FileHandle(forReadingAtPath: thumbPath) else {
                throw ApiError.notFound("Thumbnail file missing on disk")
            }
            let data = fileHandle.readDataToEndOfFile()
            fileHandle.closeFile()

            return HttpResponse(
                status: 200,
                headers: [
                    ("Content-Type", "image/jpeg"),
                    ("Cache-Control", "private, max-age=86400"),
                    ("Content-Length", "\(data.count)")
                ],
                body: .data(data)
            )
        }

        // PUT /api/files/:id/thumb
        r.add("PUT", "/api/files/:id/thumb", auth: true) { req in
            guard let id = req.params["id"],
                  let node = try ctx.store.getNode(id),
                  node.trashedAt == nil else {
                throw ApiError.notFound("Node not found")
            }

            let cl = req.body.contentLength
            guard cl <= 256 * 1024 else {
                throw ApiError.payloadTooLarge("Thumbnail exceeds 256KB")
            }

            let data = try req.body.readAll(limit: 256 * 1024)
            guard data.count >= 2, data[0] == 0xFF, data[1] == 0xD8 else {
                throw ApiError.badRequest("Invalid JPEG format: missing 0xFFD8 SOI marker")
            }

            let tmpPath = ctx.blobs.root
                .appendingPathComponent("tmp")
                .appendingPathComponent("thumb_\(id)_\(UUID().uuidString).tmp")
                .path

            try data.write(to: URL(fileURLWithPath: tmpPath), options: .atomic)
            let destPath = ctx.blobs.thumbPath(forNode: id)
            try? FileManager.default.removeItem(atPath: destPath)
            try FileManager.default.moveItem(atPath: tmpPath, toPath: destPath)

            try ctx.store.setHasThumb(id, true)
            return HttpResponse(status: 204, headers: [], body: .none)
        }
    }

    private static func streamRawRange(path: String, start: Int64, length: Int64, writer: ResponseWriter) throws {
        let fd = open(path, O_RDONLY, 0)
        guard fd >= 0 else { throw SocketError.closed }
        defer { close(fd) }

        let bufSize = 64 * 1024
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buf.deallocate() }

        var currentOffset = start
        let endOffset = start + length - 1

        while currentOffset <= endOffset {
            let toRead = min(bufSize, Int(endOffset - currentOffset + 1))
            #if canImport(Darwin) || canImport(Glibc)
            let n = pread(fd, buf, toRead, off_t(currentOffset))
            #else
            lseek(fd, off_t(currentOffset), SEEK_SET)
            let n = read(fd, buf, toRead)
            #endif
            if n <= 0 { break }
            try writer.write(buf, count: n)
            currentOffset += Int64(n)
        }
    }

    public static func formatContentDisposition(name: String, isAttachment: Bool) -> String {
        let disposition = isAttachment ? "attachment" : "inline"

        var ascii = ""
        for scalar in name.unicodeScalars {
            if scalar.isASCII && scalar.value != 0x22 && scalar.value != 0x5C {
                ascii.append(Character(scalar))
            } else {
                ascii.append("_")
            }
        }
        if ascii.isEmpty {
            ascii = "file"
        }

        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "!#$&+-.^_`|~")
        let encoded = name.addingPercentEncoding(withAllowedCharacters: allowed) ?? name

        return "\(disposition); filename=\"\(ascii)\"; filename*=UTF-8''\(encoded)"
    }

    private static func formatContentType(mime: String, name: String) -> String {
        let baseMime: String
        if mime.isEmpty || mime == "application/octet-stream" || mime == "binary/octet-stream" {
            baseMime = MimeTypes.mime(forName: name)
        } else {
            baseMime = mime
        }
        if baseMime.hasPrefix("text/") || baseMime == "application/json" || baseMime == "application/xml" || baseMime == "application/javascript" {
            if !baseMime.contains("charset=") {
                return "\(baseMime); charset=utf-8"
            }
        }
        return baseMime
    }
}
