// Unit tests for Credentials, SessionStore, RateLimiter, and constant-time string comparison.

import XCTest
@testable import ExVaultCore

final class AuthTests: XCTestCase {

    func testCredentialsGeneration() {
        var generatedPairs = Set<String>()

        for _ in 0..<100 {
            let creds = Credentials.generate()
            XCTAssertEqual(creds.username, "admin")
            XCTAssertEqual(creds.password.count, 6)
            XCTAssertTrue(creds.password.allSatisfy { $0.isNumber })

            generatedPairs.insert("\(creds.username):\(creds.password)")
        }

        XCTAssertGreaterThan(generatedPairs.count, 50, "Generated PINs should have high uniqueness")
    }

    func testSessionStoreLifecycle() {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let store = SessionStore(maxSessions: 3, ttl: 60, now: { currentTime })

        // 1. Create session: token is 64 hex characters
        let token1 = store.create()
        XCTAssertEqual(token1.count, 64)
        XCTAssertTrue(token1.allSatisfy { $0.isHexDigit })
        XCTAssertEqual(store.count(), 1)
        XCTAssertTrue(store.validate(token1))

        // 2. Add sessions up to max
        currentTime = Date(timeIntervalSince1970: 1010)
        let token2 = store.create()
        currentTime = Date(timeIntervalSince1970: 1020)
        let token3 = store.create()
        XCTAssertEqual(store.count(), 3)

        // 3. Exceed maxSessions (3) -> oldest (token1) should be evicted
        currentTime = Date(timeIntervalSince1970: 1030)
        let token4 = store.create()
        XCTAssertEqual(store.count(), 3)
        XCTAssertFalse(store.validate(token1), "Oldest session token1 should have been evicted")
        XCTAssertTrue(store.validate(token2))
        XCTAssertTrue(store.validate(token3))
        XCTAssertTrue(store.validate(token4))

        // 4. Sliding expiration
        // token2 was validated at t=1030, so its expiresAt should be 1030 + 60 = 1090
        currentTime = Date(timeIntervalSince1970: 1080)
        XCTAssertTrue(store.validate(token2), "token2 should still be valid due to sliding extension")

        // 5. Expiration
        currentTime = Date(timeIntervalSince1970: 1200)
        XCTAssertFalse(store.validate(token2))
        XCTAssertEqual(store.count(), 0)

        // 6. Destroy
        currentTime = Date(timeIntervalSince1970: 1200)
        let token5 = store.create()
        XCTAssertTrue(store.validate(token5))
        store.destroy(token5)
        XCTAssertFalse(store.validate(token5))
        XCTAssertEqual(store.count(), 0)
    }

    func testRateLimiterLockoutAndSuccess() {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let limiter = RateLimiter(maxFailures: 5, window: 60, lockout: 60, now: { currentTime })

        let ip1 = "192.168.1.10"
        let ip2 = "192.168.1.20"

        // Initially allowed
        XCTAssertNil(limiter.allowed(ip: ip1))
        XCTAssertNil(limiter.allowed(ip: ip2))

        // 4 failures -> still allowed
        for _ in 0..<4 {
            limiter.recordFailure(ip: ip1)
        }
        XCTAssertNil(limiter.allowed(ip: ip1))

        // 5th failure -> locked out
        limiter.recordFailure(ip: ip1)
        guard let waitTime = limiter.allowed(ip: ip1) else {
            XCTFail("Should be locked out")
            return
        }
        XCTAssertEqual(waitTime, 60.0)

        // IP2 is not locked out
        XCTAssertNil(limiter.allowed(ip: ip2))

        // Advance 30 seconds -> still locked
        currentTime = Date(timeIntervalSince1970: 1030)
        let remaining = limiter.allowed(ip: ip1)
        XCTAssertNotNil(remaining)
        XCTAssertEqual(remaining, 30.0)

        // Advance 61 seconds total -> lockout ended
        currentTime = Date(timeIntervalSince1970: 1061)
        XCTAssertNil(limiter.allowed(ip: ip1))

        // Test recordSuccess clears failures
        currentTime = Date(timeIntervalSince1970: 2000)
        for _ in 0..<4 {
            limiter.recordFailure(ip: ip1)
        }
        limiter.recordSuccess(ip: ip1)
        // Now 1 more failure should not lock out
        limiter.recordFailure(ip: ip1)
        XCTAssertNil(limiter.allowed(ip: ip1))
    }

    func testRateLimiterMaxEntriesBounded() {
        var currentTime = Date(timeIntervalSince1970: 1000)
        let limiter = RateLimiter(maxFailures: 5, window: 60, lockout: 60, maxEntries: 256, now: { currentTime })

        // Add 300 different IPs
        for i in 1...300 {
            currentTime = currentTime.addingTimeInterval(0.1)
            let ip = "10.0.\(i / 255).\(i % 255)"
            limiter.recordFailure(ip: ip)
        }

        XCTAssertLessThanOrEqual(limiter.trackedIPCount, 256, "RateLimiter must not exceed maxEntries")
    }

    func testConstantTimeEquals() {
        XCTAssertTrue(Net.constantTimeEquals("admin", "admin"))
        XCTAssertFalse(Net.constantTimeEquals("admin", "root"))
        XCTAssertFalse(Net.constantTimeEquals("short", "muchlongerpassword"))
        XCTAssertFalse(Net.constantTimeEquals("muchlongerpassword", "short"))
        XCTAssertFalse(Net.constantTimeEquals("", "admin"))
        XCTAssertFalse(Net.constantTimeEquals("admin", ""))
        XCTAssertTrue(Net.constantTimeEquals("", ""))
        XCTAssertTrue(Net.constantTimeEquals("secret12345678", "secret12345678"))
        XCTAssertFalse(Net.constantTimeEquals("secret12345678", "secret12345679"))
    }
}
