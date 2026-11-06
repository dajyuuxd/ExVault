// Node management endpoints: listing, hierarchy, folders, rename, move, trash, restore, purge, search, and tags.

import Foundation

public enum NodesApi: ApiModule {
    private struct CreateFolderRequest: Decodable {
        let parentId: String?
        let name: String
    }

    private struct RenameRequest: Decodable {
        let name: String
    }

    private struct MoveRequest: Decodable {
        let ids: [String]
        let parentId: String?
    }

    private struct BatchIdsRequest: Decodable {
        let ids: [String]
    }

    private struct ApplyTagsRequest: Decodable {
        let ids: [String]
        let add: [Int64]?
        let remove: [Int64]?
    }

    private struct ParentInfo: Codable {
        let id: String?
        let name: String
    }

    public struct BreadcrumbItem: Codable {
        public let id: String
        public let name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    private struct NodeListResponse: Codable {
        let parent: ParentInfo?
        let path: [BreadcrumbItem]
        let items: [Node]
    }

    private struct SearchNodeItem: Encodable {
        let id: String
        let parentId: String?
        let kind: String
        let name: String
        let size: Int64
        let storedSize: Int64
        let mime: String
        let codec: String
        let hasThumb: Bool
        let tagIds: [Int64]
        let createdAt: Int64
        let modifiedAt: Int64
        let trashedAt: Int64?
        let pathText: String

        init(node: Node, pathText: String) {
            self.id = node.id
            self.parentId = node.parentId
            self.kind = node.kind
            self.name = node.name
            self.size = node.size
            self.storedSize = node.storedSize
            self.mime = node.mime
            self.codec = node.codec
            self.hasThumb = node.hasThumb
            self.tagIds = node.tagIds
            self.createdAt = node.createdAt
            self.modifiedAt = node.modifiedAt
            self.trashedAt = node.trashedAt
            self.pathText = pathText
        }
    }

    public static func register(_ r: Router, _ ctx: ApiContext) {
        // GET /api/nodes
        r.add("GET", "/api/nodes", auth: true) { req in
            let rawParent = req.query["parent"]
            let parentId: String? = (rawParent == nil || rawParent == "root" || rawParent == "") ? nil : rawParent

            if let pId = parentId {
                guard let parentNode = try ctx.store.getNode(pId), parentNode.trashedAt == nil else {
                    throw ApiError.notFound("Parent folder not found")
                }
                guard parentNode.kind == "folder" else {
                    throw ApiError.badRequest("Parent is not a folder")
                }
            }

            let sortStr = req.query["sort"] ?? "name"
            let orderStr = req.query["order"] ?? "asc"
            let sortKey = SortKey(rawValue: sortStr.lowercased()) ?? .name
            let sortOrder = SortOrder(rawValue: orderStr.lowercased()) ?? .asc

            let items = try ctx.store.listChildren(parentId: parentId, sort: sortKey, order: sortOrder)
            let rawPath = try ctx.store.breadcrumb(of: parentId)
            let path = rawPath.map { BreadcrumbItem(id: $0.id, name: $0.name) }

            var parentInfo: ParentInfo? = nil
            if let pId = parentId, let pNode = try ctx.store.getNode(pId) {
                parentInfo = ParentInfo(id: pNode.id, name: pNode.name)
            }

            let responseObj = NodeListResponse(parent: parentInfo, path: path, items: items)
            return HttpResponse.json(responseObj)
        }

        // GET /api/nodes/:id
        r.add("GET", "/api/nodes/:id", auth: true) { req in
            guard let id = req.params["id"],
                  let node = try ctx.store.getNode(id),
                  node.trashedAt == nil else {
                throw ApiError.notFound("Node not found")
            }
            return HttpResponse.json(node)
        }

        // POST /api/folders
        r.add("POST", "/api/folders", auth: true) { req in
            let body = try ctx.json(req, CreateFolderRequest.self)
            let parentId = (body.parentId == "root") ? nil : body.parentId
            let folder = try ctx.store.createFolder(parentId: parentId, name: body.name)
            return HttpResponse.json(folder, status: 201)
        }

        // PATCH /api/nodes/:id
        r.add("PATCH", "/api/nodes/:id", auth: true) { req in
            guard let id = req.params["id"] else {
                throw ApiError.notFound("Node not found")
            }
            let body = try ctx.json(req, RenameRequest.self)
            let updated = try ctx.store.rename(id, to: body.name)
            return HttpResponse.json(updated)
        }

        // POST /api/nodes/move
        r.add("POST", "/api/nodes/move", auth: true) { req in
            let body = try ctx.json(req, MoveRequest.self)
            guard body.ids.count <= 5000 else {
                throw ApiError.badRequest("Exceeded maximum batch limit of 5000 IDs")
            }
            let targetParent = (body.parentId == "root") ? nil : body.parentId
            let moved = try ctx.store.move(body.ids, to: targetParent)
            return HttpResponse.json(["items": moved])
        }

        // POST /api/nodes/trash
        r.add("POST", "/api/nodes/trash", auth: true) { req in
            let body = try ctx.json(req, BatchIdsRequest.self)
            guard body.ids.count <= 5000 else {
                throw ApiError.badRequest("Exceeded maximum batch limit of 5000 IDs")
            }
            let count = try ctx.store.trash(body.ids)
            return HttpResponse.json(["count": count])
        }

        // POST /api/nodes/restore
        r.add("POST", "/api/nodes/restore", auth: true) { req in
            let body = try ctx.json(req, BatchIdsRequest.self)
            guard body.ids.count <= 5000 else {
                throw ApiError.badRequest("Exceeded maximum batch limit of 5000 IDs")
            }
            let count = try ctx.store.restore(body.ids)
            return HttpResponse.json(["count": count])
        }

        // POST /api/nodes/purge
        r.add("POST", "/api/nodes/purge", auth: true) { req in
            let body = try ctx.json(req, BatchIdsRequest.self)
            guard body.ids.count <= 5000 else {
                throw ApiError.badRequest("Exceeded maximum batch limit of 5000 IDs")
            }
            let (count, deletedBlobs, deletedThumbs) = try ctx.store.purge(body.ids)
            for blobId in deletedBlobs {
                ctx.blobs.delete(blobId: blobId)
            }
            for nodeId in deletedThumbs {
                ctx.blobs.deleteThumb(nodeId: nodeId)
            }
            return HttpResponse.json(["count": count])
        }

        // GET /api/trash
        r.add("GET", "/api/trash", auth: true) { _ in
            let items = try ctx.store.listTrash()
            return HttpResponse.json(["items": items])
        }

        // POST /api/trash/empty
        r.add("POST", "/api/trash/empty", auth: true) { _ in
            let (count, deletedBlobs, deletedThumbs) = try ctx.store.emptyTrash()
            for blobId in deletedBlobs {
                ctx.blobs.delete(blobId: blobId)
            }
            for nodeId in deletedThumbs {
                ctx.blobs.deleteThumb(nodeId: nodeId)
            }
            return HttpResponse.json(["count": count])
        }

        // GET /api/search
        r.add("GET", "/api/search", auth: true) { req in
            let q = req.query["q"]?.trimmingCharacters(in: .whitespaces)
            let tagStr = req.query["tag"]?.trimmingCharacters(in: .whitespaces)
            let tagId = tagStr.flatMap { Int64($0) }

            if (q == nil || q?.isEmpty == true) && tagId == nil {
                throw ApiError.badRequest("At least query parameter 'q' or 'tag' is required")
            }

            let results = try ctx.store.search(q: (q?.isEmpty == true ? nil : q), tagId: tagId)
            let items = results.map { SearchNodeItem(node: $0.node, pathText: $0.pathText) }
            return HttpResponse.json(["items": items])
        }

        // POST /api/nodes/tag
        r.add("POST", "/api/nodes/tag", auth: true) { req in
            let body = try ctx.json(req, ApplyTagsRequest.self)
            guard body.ids.count <= 5000 else {
                throw ApiError.badRequest("Exceeded maximum batch limit of 5000 IDs")
            }
            let updated = try ctx.store.applyTags(
                ids: body.ids,
                add: body.add ?? [],
                remove: body.remove ?? []
            )
            return HttpResponse.json(["items": updated])
        }
    }
}
