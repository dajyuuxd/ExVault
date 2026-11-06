// Smoke test verifying basic version string.

import XCTest
@testable import ExVaultCore

final class SmokeTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(ExVaultInfo.version, "1.0.2")
    }
}
