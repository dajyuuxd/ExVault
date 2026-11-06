// Chunked upload endpoints: create upload, append chunks, finish processing, status inquiry, and cancel.

import Foundation

public enum UploadApi: ApiModule {
    private struct CreateUploadRequest: Decodable {
        let parentId: String?
        let name: String
        let size: Int64
        let mime: String?
        let lastModified: Int64?
        let compress: String?
    }

    public static func register(_ r: Router, _ ctx: ApiContext) {
        // POST /api/upload
        r.add("POST", "/api/upload", auth: true) { req in
            let body = try ctx.json(req, CreateUploadRequest.self)
            let parentId = (body.parentId == "root") ? nil : body.parentId
            let shouldCompress = (body.compress?.lowercased() != "off")

            let info = try ctx.uploads.create(
                parentId: parentId,
                name: body.name,
                size: body.size,
                mime: body.mime ?? "",
                lastModified: body.lastModified,
                compress: shouldCompress
            )

            let payload: [String: Any] = [
                "uploadId": info.id,
                "offset": 0,
                "chunkSize": ctx.config.uploadChunkSize
            ]
            return HttpResponse.jsonRaw(payload, status: 201)
        }

        // GET /api/upload/:id
        r.add("GET", "/api/upload/:id", auth: true) { req in
            guard let id = req.params["id"] else {
                throw ApiError.badRequest("Missing upload id")
            }
            let info = try ctx.uploads.info(id: id)
            var node: Node? = nil
            if info.state == "done", let nodeId = info.nodeId {
                node = try ctx.store.getNode(nodeId)
            }

            var nodeJson: Any = NSNull()
            if let n = node, let data = try? JSONEncoder().encode(n) {
                nodeJson = (try? JSONSerialization.jsonObject(with: data, options: [])) ?? NSNull()
            }

            let payload: [String: Any] = [
                "uploadId": info.id,
                "state": info.state,
                "offset": info.received,
                "size": info.size,
                "node": nodeJson,
                "error": info.error != nil ? info.error! : NSNull()
            ]
            return HttpResponse.jsonRaw(payload)
        }

        // PUT /api/upload/:id?offset=N
        r.add("PUT", "/api/upload/:id", auth: true) { req in
            guard let id = req.params["id"] else {
                throw ApiError.badRequest("Missing upload id")
            }
            guard let offsetStr = req.query["offset"], let offset = Int64(offsetStr) else {
                throw ApiError.badRequest("Query parameter 'offset' is required")
            }

            let cl = req.body.contentLength
            guard cl > 0 else {
                throw ApiError.lengthRequired("Content-Length header is required and must be greater than 0")
            }
            guard cl <= 8 * 1024 * 1024 else {
                throw ApiError.payloadTooLarge("Upload chunk cannot exceed 8MB")
            }

            let newReceived = try ctx.uploads.appendChunk(id: id, offset: offset, length: Int(cl)) { buf, maxCount in
                try req.body.read(into: buf, max: maxCount)
            }

            return HttpResponse.json(["offset": newReceived])
        }

        // POST /api/upload/:id/finish
        r.add("POST", "/api/upload/:id/finish", auth: true) { req in
            guard let id = req.params["id"] else {
                throw ApiError.badRequest("Missing upload id")
            }

            try ctx.uploads.finish(id: id)
            let info = try ctx.uploads.info(id: id)

            if info.state == "done", let nodeId = info.nodeId, let node = try ctx.store.getNode(nodeId) {
                var nodeJson: Any = NSNull()
                if let data = try? JSONEncoder().encode(node) {
                    nodeJson = (try? JSONSerialization.jsonObject(with: data, options: [])) ?? NSNull()
                }
                let payload: [String: Any] = [
                    "state": "done",
                    "node": nodeJson
                ]
                return HttpResponse.jsonRaw(payload, status: 200)
            } else {
                return HttpResponse.jsonRaw(["state": "processing"], status: 202)
            }
        }

        // DELETE /api/upload/:id
        r.add("DELETE", "/api/upload/:id", auth: true) { req in
            guard let id = req.params["id"] else {
                throw ApiError.badRequest("Missing upload id")
            }
            try ctx.uploads.cancel(id: id)
            return HttpResponse(status: 204, headers: [], body: .none)
        }
    }
}
