// Main server facade: initializes database, storage, credentials, HTTP routing, and static file serving.

import Foundation

public enum ExVaultInfo {
    public static let version = "1.0"
}

public struct VaultConfig {
    public var dataDir: URL            // <Documents>/ExVault
    public var webRoot: URL            // Web/ directory
    public var port: UInt16            // default 8080
    public var maxConnections: Int     // default 8
    public var maxSessions: Int        // default 3
    public var reserveFreeBytes: Int64 // default 300 * 1024 * 1024
    public var uploadChunkSize: Int    // default 4 * 1024 * 1024

    public init(
        dataDir: URL,
        webRoot: URL,
        port: UInt16 = 8080,
        maxConnections: Int = 8,
        maxSessions: Int = 3,
        reserveFreeBytes: Int64 = 300 * 1024 * 1024,
        uploadChunkSize: Int = 4 * 1024 * 1024
    ) {
        self.dataDir = dataDir
        self.webRoot = webRoot
        self.port = port
        self.maxConnections = maxConnections
        self.maxSessions = maxSessions
        self.reserveFreeBytes = reserveFreeBytes
        self.uploadChunkSize = uploadChunkSize
    }
}

public final class VaultServer {
    public let config: VaultConfig
    public let credentials: Credentials
    public private(set) var boundPort: UInt16 = 0

    public let db: Database
    public let store: VaultStore
    public let blobs: BlobStore
    public let uploads: UploadManager
    public let sessions: SessionStore
    public let limiter: RateLimiter
    public let staticFiles: StaticFiles

    internal let ctx: ApiContext
    internal let router: Router
    private var httpServer: HttpServer?

    public init(config: VaultConfig) throws {
        self.config = config

        // 1. Create data directory and exclude from backup
        try FileManager.default.createDirectory(at: config.dataDir, withIntermediateDirectories: true, attributes: nil)
        var dirURL = config.dataDir
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? dirURL.setResourceValues(resourceValues)

        // 2. Open SQLite database & run schema migrations
        let dbPath = config.dataDir.appendingPathComponent("vault.db").path
        let database = try Database(path: dbPath)
        self.db = database

        // 3. Initialize BlobStore & VaultStore
        let blobStore = try BlobStore(root: config.dataDir)
        self.blobs = blobStore
        let vaultStore = VaultStore(db: database)
        self.store = vaultStore

        // 4. Initialize UploadManager & clean up interrupted uploads
        let uploadManager = UploadManager(store: vaultStore, blobs: blobStore, config: config)
        uploadManager.cleanupAtStartup()
        self.uploads = uploadManager

        // 5. Generate credentials, session store, rate limiter, static files
        let creds = Credentials.generate()
        self.credentials = creds
        let sessionStore = SessionStore(maxSessions: config.maxSessions)
        self.sessions = sessionStore
        let rateLimiter = RateLimiter()
        self.limiter = rateLimiter
        let staticFileServer = StaticFiles(root: config.webRoot)
        self.staticFiles = staticFileServer

        // 6. Create ApiContext and Router
        let apiCtx = ApiContext(
            config: config,
            credentials: creds,
            db: database,
            store: vaultStore,
            blobs: blobStore,
            uploads: uploadManager,
            sessions: sessionStore,
            limiter: rateLimiter,
            staticFiles: staticFileServer
        )
        self.ctx = apiCtx

        let r = Router()
        self.router = r

        // Static file routes
        r.add("GET", "/", auth: false) { [weak self] req in
            guard let self = self else { return HttpResponse.empty(404) }
            return self.staticFiles.serve(urlPath: "/", ifNoneMatch: req.headers["if-none-match"])
        }
        r.add("GET", "/css/*", auth: false) { [weak self] req in
            guard let self = self else { return HttpResponse.empty(404) }
            return self.staticFiles.serve(urlPath: req.path, ifNoneMatch: req.headers["if-none-match"])
        }
        r.add("GET", "/js/*", auth: false) { [weak self] req in
            guard let self = self else { return HttpResponse.empty(404) }
            return self.staticFiles.serve(urlPath: req.path, ifNoneMatch: req.headers["if-none-match"])
        }
        r.add("GET", "/favicon.ico", auth: false) { [weak self] req in
            guard let self = self else { return HttpResponse.empty(404) }
            return self.staticFiles.serve(urlPath: req.path, ifNoneMatch: req.headers["if-none-match"])
        }

        // Register core API modules
        AuthApi.register(r, apiCtx)
        NodesApi.register(r, apiCtx)
        TagsApi.register(r, apiCtx)
        StatsApi.register(r, apiCtx)
    }

    public func start() throws {
        guard boundPort == 0 else { return }

        let server = HttpServer(maxConnections: config.maxConnections) { [weak self] req in
            guard let self = self else { return HttpResponse.empty(503) }
            return self.router.dispatch(req) { [weak self] r in
                guard let self = self else { return false }
                let token = r.cookies["exv_sid"]
                return self.sessions.validate(token)
            }
        }
        self.httpServer = server
        let actualPort = try server.start(port: config.port)
        self.boundPort = actualPort
        Log.info("ExVault server started on port \(actualPort)")
    }

    public func stop() {
        httpServer?.stop()
        httpServer = nil
        boundPort = 0
        Log.info("ExVault server stopped")
    }

    public func localAddresses() -> [String] {
        return Net.localIPv4Addresses()
    }

    public func activeSessionCount() -> Int {
        return sessions.count()
    }

    public func diskFreeBytes() -> Int64 {
        return blobs.diskFree()
    }
}
