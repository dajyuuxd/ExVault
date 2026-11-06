// Public configuration and entry point for ExVaultCore.

import Foundation

public enum ExVaultInfo {
    public static let version = "1.0"
}

public struct VaultConfig {
    public var dataDir: URL            // <Documents>/ExVault
    public var webRoot: URL            // Web/ directory
    public var port: UInt16            // default 8080
    public var maxConnections: Int     // 8
    public var maxSessions: Int        // 3
    public var reserveFreeBytes: Int64 // 300 * 1024 * 1024
    public var uploadChunkSize: Int    // 4 * 1024 * 1024

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

public struct Credentials {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}
