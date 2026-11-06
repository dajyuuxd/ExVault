// Shared context for API modules, providing dependencies, body decoding, and JSON utilities.

import Foundation

public protocol ApiModule {
    static func register(_ r: Router, _ ctx: ApiContext)
}

public final class ApiContext {
    public let config: VaultConfig
    public let credentials: Credentials
    public let db: Database
    public let store: VaultStore
    public let blobs: BlobStore
    public let uploads: UploadManager
    public let sessions: SessionStore
    public let limiter: RateLimiter
    public let staticFiles: StaticFiles

    public init(
        config: VaultConfig,
        credentials: Credentials,
        db: Database,
        store: VaultStore,
        blobs: BlobStore,
        uploads: UploadManager,
        sessions: SessionStore,
        limiter: RateLimiter,
        staticFiles: StaticFiles
    ) {
        self.config = config
        self.credentials = credentials
        self.db = db
        self.store = store
        self.blobs = blobs
        self.uploads = uploads
        self.sessions = sessions
        self.limiter = limiter
        self.staticFiles = staticFiles
    }

    public func json<T: Decodable>(_ req: HttpRequest, _ type: T.Type) throws -> T {
        let data = try req.body.readAll(limit: 1024 * 1024)
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ApiError.badRequest("Invalid JSON body: \(error.localizedDescription)")
        }
    }
}
