// Tag management endpoints: list, create, update, and delete.

import Foundation

public enum TagsApi: ApiModule {
    private struct CreateTagRequest: Decodable {
        let name: String
        let color: String?
    }

    private struct UpdateTagRequest: Decodable {
        let name: String?
        let color: String?
    }

    public static func register(_ r: Router, _ ctx: ApiContext) {
        // GET /api/tags
        r.add("GET", "/api/tags", auth: true) { _ in
            let tags = try ctx.store.listTags()
            return HttpResponse.json(["items": tags])
        }

        // POST /api/tags
        r.add("POST", "/api/tags", auth: true) { req in
            let body = try ctx.json(req, CreateTagRequest.self)
            let tag = try ctx.store.createTag(name: body.name, color: body.color)
            return HttpResponse.json(tag, status: 201)
        }

        // PATCH /api/tags/:id
        r.add("PATCH", "/api/tags/:id", auth: true) { req in
            guard let idStr = req.params["id"], let id = Int64(idStr) else {
                throw ApiError.badRequest("Invalid tag id")
            }
            let body = try ctx.json(req, UpdateTagRequest.self)
            let updated = try ctx.store.updateTag(id: id, name: body.name, color: body.color)
            return HttpResponse.json(updated)
        }

        // DELETE /api/tags/:id
        r.add("DELETE", "/api/tags/:id", auth: true) { req in
            guard let idStr = req.params["id"], let id = Int64(idStr) else {
                throw ApiError.badRequest("Invalid tag id")
            }
            try ctx.store.deleteTag(id: id)
            return HttpResponse(status: 204, headers: [], body: .none)
        }
    }
}
