// In-memory brute-force rate limiter per IP address with lockout and bounded entry retention.

import Foundation

public final class RateLimiter {
    private struct Entry {
        var failureTimes: [Date]
        var lockedUntil: Date?
        var lastUpdated: Date
    }

    private let maxFailures: Int
    private let window: TimeInterval
    private let lockout: TimeInterval
    private let maxEntries: Int
    private let nowProvider: () -> Date
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    public init(
        maxFailures: Int = 5,
        window: TimeInterval = 60,
        lockout: TimeInterval = 60,
        maxEntries: Int = 256,
        now: @escaping () -> Date = Date.init
    ) {
        self.maxFailures = maxFailures
        self.window = window
        self.lockout = lockout
        self.maxEntries = maxEntries
        self.nowProvider = now
    }

    /// Returns nil if allowed, or remaining lockout seconds (rounded up) if locked.
    public func allowed(ip: String) -> TimeInterval? {
        lock.lock()
        defer { lock.unlock() }

        let now = nowProvider()
        cleanOldEntries(now: now)

        guard let entry = entries[ip] else {
            return nil
        }

        if let lockedUntil = entry.lockedUntil {
            if lockedUntil > now {
                let remaining = lockedUntil.timeIntervalSince(now)
                return max(1.0, ceil(remaining))
            }
        }
        return nil
    }

    public func recordFailure(ip: String) {
        lock.lock()
        defer { lock.unlock() }

        let now = nowProvider()
        cleanOldEntries(now: now)

        var entry = entries[ip] ?? Entry(failureTimes: [], lockedUntil: nil, lastUpdated: now)

        let cutoff = now.addingTimeInterval(-window)
        entry.failureTimes = entry.failureTimes.filter { $0 >= cutoff }
        entry.failureTimes.append(now)
        entry.lastUpdated = now

        if entry.failureTimes.count >= maxFailures {
            entry.lockedUntil = now.addingTimeInterval(lockout)
        }

        if entries[ip] == nil && entries.count >= maxEntries {
            if let oldest = entries.min(by: { $0.value.lastUpdated < $1.value.lastUpdated }) {
                entries.removeValue(forKey: oldest.key)
            }
        }

        entries[ip] = entry
    }

    public func recordSuccess(ip: String) {
        lock.lock()
        defer { lock.unlock() }

        entries.removeValue(forKey: ip)
    }

    public var trackedIPCount: Int {
        lock.lock()
        defer { lock.unlock() }
        cleanOldEntries(now: nowProvider())
        return entries.count
    }

    private func cleanOldEntries(now: Date) {
        let maxAge = max(window, lockout)
        let cutoff = now.addingTimeInterval(-maxAge)
        entries = entries.filter { entry in
            if let locked = entry.value.lockedUntil, locked > now {
                return true
            }
            return entry.value.lastUpdated >= cutoff
        }
    }
}
