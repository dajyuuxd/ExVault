// Server credentials and generation with unambiguous character sets.

import Foundation

public struct Credentials: Equatable {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    // Unambiguous character tables:
    // Username: 23 chars (omits i, l, o)
    private static let userChars = Array("abcdefghjkmnpqrstuvwxyz")
    // Password: 31 chars (omits i, l, o, 0, 1)
    private static let passChars = Array("abcdefghjkmnpqrstuvwxyz23456789")

    public static func generate() -> Credentials {
        var rng = SystemRandomNumberGenerator()

        var user = ""
        user.reserveCapacity(5)
        for _ in 0..<5 {
            let idx = Int.random(in: 0..<userChars.count, using: &rng)
            user.append(userChars[idx])
        }

        var pass = ""
        pass.reserveCapacity(8)
        for _ in 0..<8 {
            let idx = Int.random(in: 0..<passChars.count, using: &rng)
            pass.append(passChars[idx])
        }

        return Credentials(username: user, password: pass)
    }
}
