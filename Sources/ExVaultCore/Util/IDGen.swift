// Cryptographically secure random identifier generator for nodes, blobs, and sessions.

import Foundation

public enum IDGen {
    private static let hexDigits: [Character] = [
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"
    ]

    /// Generates a 24-character lowercase hex identifier from 12 random bytes.
    public static func newID() -> String {
        return randomHex(byteCount: 12)
    }

    /// Generates a 64-character lowercase hex session token from 32 random bytes.
    public static func token() -> String {
        return randomHex(byteCount: 32)
    }

    private static func randomHex(byteCount: Int) -> String {
        var rng = SystemRandomNumberGenerator()
        var result = String()
        result.reserveCapacity(byteCount * 2)
        for _ in 0..<byteCount {
            let byte = UInt8.random(in: 0...255, using: &rng)
            let high = Int(byte >> 4)
            let low = Int(byte & 0x0F)
            result.append(hexDigits[high])
            result.append(hexDigits[low])
        }
        return result
    }
}
