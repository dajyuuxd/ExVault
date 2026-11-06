// Server credentials and generation with simple username and 6-digit numeric PIN.

import Foundation

public struct Credentials: Equatable {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    /// Generates credentials with username 'admin' and a 6-digit numeric PIN (e.g. "582194").
    public static func generate() -> Credentials {
        let pin = String(format: "%06d", Int.random(in: 100000...999999))
        return Credentials(username: "admin", password: pin)
    }
}
