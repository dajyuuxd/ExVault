// Streaming ZIP download endpoint for multi-file and folder archiving.

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum ZipApi: ApiModule {

    public static func validate(entries: [ZipEntry]) throws -> Int64 {
        guard !entries.isEmpty else {
            throw ApiError.badRequest("No entries to archive")
        }
        if entries.count > 65535 {
            throw ApiError.payloadTooLarge("Archive exceeds 65535 entries", code: "too_large")
        }
        let total = ZipWriter.totalLength(entries: entries)
        if total > 0xFFFFFFFF {
            throw ApiError.payloadTooLarge("Archive exceeds 4GB limit", code: "too_large")
        }
        return total
    }

    public static func register(_ r: Router, _ ctx: ApiContext) {
        // POST /api/zip
        r.add("POST", "/api/zip", auth: true) { req in
            let bodyData = try req.body.readAll(limit: 1024 * 1024)
            let bodyStr = String(data: bodyData, encoding: .utf8) ?? ""

            var ids: [String] = []
            let trimmed = bodyStr.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("{") {
                if let json = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8), options: []) as? [String: Any],
                   let rawIds = json["ids"] as? [String] {
                    ids = rawIds
                }
            } else {
                let pairs = bodyStr.split(separator: "&", omittingEmptySubsequences: true)
                for pair in pairs {
                    let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    guard parts.count > 0 else { continue }
                    let rawKey = String(parts[0]).replacingOccurrences(of: "+", with: " ")
                    let key = Net.percentDecode(rawKey) ?? rawKey
                    if key == "ids" && parts.count > 1 {
                        let rawVal = String(parts[1]).replacingOccurrences(of: "+", with: " ")
                        let val = Net.percentDecode(rawVal) ?? rawVal
                        let splitIds = val.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                        ids.append(contentsOf: splitIds)
                    }
                }
            }

            ids = ids.filter { !$0.isEmpty }
            guard !ids.isEmpty else {
                throw ApiError.badRequest("No ids provided")
            }

            let entries = try ctx.store.zipEntries(forIds: ids)
            let totalLength = try validate(entries: entries)

            let filename: String
            if ids.count == 1, let firstEntry = entries.first, let nodeName = firstEntry.node?.name {
                let clean = nodeName
                    .replacingOccurrences(of: "/", with: "_")
                    .replacingOccurrences(of: "\\", with: "_")
                    .trimmingCharacters(in: .whitespaces)
                let base = clean.isEmpty ? "exvault" : clean
                filename = base.lowercased().hasSuffix(".zip") ? base : "\(base).zip"
            } else {
                filename = "exvault.zip"
            }

            let contentDisposition = FilesApi.formatContentDisposition(name: filename, isAttachment: true)

            return HttpResponse(
                status: 200,
                headers: [
                    ("Content-Type", "application/zip"),
                    ("Content-Disposition", contentDisposition),
                    ("Content-Length", "\(totalLength)"),
                    ("Cache-Control", "private, no-cache")
                ],
                body: .stream(length: totalLength) { writer in
                    let zipWriter = ZipWriter(entries: entries)
                    try zipWriter.write(to: writer) { entry, sink in
                        guard let nodeId = entry.node?.id,
                              let info = try ctx.store.fileBlobInfo(nodeId) else {
                            throw ApiError.notFound("File blob not found for entry: \(entry.path)")
                        }
                        let blobPath = ctx.blobs.path(forBlob: info.blobId)
                        let fd = open(blobPath, O_RDONLY, 0)
                        guard fd >= 0 else {
                            throw SocketError.closed
                        }
                        defer { close(fd) }

                        if info.codec == 0 {
                            let bufferSize = 64 * 1024
                            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
                            defer { buf.deallocate() }
                            var offset: Int64 = 0
                            while offset < info.size {
                                let toRead = Swift.min(bufferSize, Int(info.size - offset))
                                #if canImport(Darwin) || canImport(Glibc)
                                let n = pread(fd, buf, toRead, off_t(offset))
                                #else
                                lseek(fd, off_t(offset), SEEK_SET)
                                let n = read(fd, buf, toRead)
                                #endif
                                if n <= 0 { break }
                                try sink(UnsafeRawBufferPointer(start: buf, count: n))
                                offset += Int64(n)
                            }
                        } else {
                            try Compressor.decompress(from: fd) { chunk in
                                try sink(chunk)
                            }
                        }
                    }
                }
            )
        }
    }
}
