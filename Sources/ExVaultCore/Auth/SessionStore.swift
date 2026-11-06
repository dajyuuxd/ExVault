// In-memory session store with TTL, LRU-style eviction, and sliding expiration.

import Foundation

public final class SessionStore {
    private struct Session {
        let token: String
        var expiresAt: Date
        var lastAccessedAt: Date
    }

    private let maxSessions: Int
    private let ttl: TimeInterval
    private let nowProvider: () -> Date
    private let lock = NSLock()
    private var sessions: [String: Session] = [:]

    public init(
        maxSessions: Int = 3,
        ttl: TimeInterval = 7 * 24 * 3600,
        now: @escaping () -> Date = Date.init
    ) {
        self.maxSessions = maxSessions
        self.ttl = ttl
        self.nowProvider = now
    }

    /// Creates a new session returning a 64-character lowercase hex token (32 random bytes).
    /// If session count exceeds maxSessions, the oldest session is evicted.
    public func create() -> String {
        lock.lock()
        defer { lock.unlock() }

        cleanExpired()

        var rng = SystemRandomNumberGenerator()
        var bytes = [UInt8](repeating: 0, count: 32)
        for i in 0..<32 {
            bytes[i] = UInt8.random(in: 0...255, using: &rng)
        }
        let token = Net.hex(Data(bytes))

        while sessions.count >= maxSessions {
            if let oldest = sessions.values.min(by: { $0.lastAccessedAt < $1.lastAccessedAt }) {
                sessions.removeValue(forKey: oldest.token)
            } else {
                break
            }
        }

        let now = nowProvider()
        sessions[token] = Session(
            token: token,
            expiresAt: now.addingTimeInterval(ttl),
            lastAccessedAt: now
        )
        return token
    }

    /// Validates token. If valid and unexpired, refreshes expiration (sliding) and returns true.
    public func validate(_ token: String?) -> Bool {
        guard let token = token, !token.isEmpty else { return false }
        lock.lock()
        defer { lock.unlock() }

        cleanExpired()

        guard var session = sessions[token] else {
            return false
        }
        let now = nowProvider()
        if session.expiresAt <= now {
            sessions.removeValue(forKey: token)
            return false
        }

        // Sliding window extension
        session.expiresAt = now.addingTimeInterval(ttl)
        session.lastAccessedAt = now
        sessions[token] = session
        return true
    }

    public func destroy(_ token: String?) {
        guard let token = token, !token.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        sessions.removeValue(forKey: token)
    }

    public func count() -> Int {
        lock.lock()
        defer { lock.unlock() }
        cleanExpired()
        return sessions.count
    }

    private func cleanExpired() {
        let now = nowProvider()
        sessions = sessions.filter { $0.value.expiresAt > now }
    }
}
