// Unit tests for HTTP RangeParser.

import XCTest
@testable import ExVaultCore

final class RangeParserTests: XCTestCase {

    func testRangeParserTableFromDocs() {
        let size: Int64 = 10

        // 1. bytes=0-0 -> partial(0, 0)
        XCTAssertEqual(RangeParser.parse(header: "bytes=0-0", size: size), .partial(start: 0, end: 0))

        // 2. bytes=5- -> partial(5, 9)
        XCTAssertEqual(RangeParser.parse(header: "bytes=5-", size: size), .partial(start: 5, end: 9))

        // 3. bytes=-5 -> partial(5, 9)
        XCTAssertEqual(RangeParser.parse(header: "bytes=-5", size: size), .partial(start: 5, end: 9))

        // 4. bytes=0-999999 (clamped to size - 1) -> partial(0, 9)
        XCTAssertEqual(RangeParser.parse(header: "bytes=0-999999", size: size), .partial(start: 0, end: 9))

        // 5. bytes=9999- (start >= size) -> invalid
        XCTAssertEqual(RangeParser.parse(header: "bytes=9999-", size: size), .invalid)

        // 6. bytes=a-b -> invalid
        XCTAssertEqual(RangeParser.parse(header: "bytes=a-b", size: size), .invalid)

        // 7. bytes=0-1,5-6 (multiple ranges) -> none
        XCTAssertEqual(RangeParser.parse(header: "bytes=0-1,5-6", size: size), .none)

        // 8. size == 0 with Range -> invalid
        XCTAssertEqual(RangeParser.parse(header: "bytes=0-0", size: 0), .invalid)
        XCTAssertEqual(RangeParser.parse(header: "bytes=0-", size: 0), .invalid)
        XCTAssertEqual(RangeParser.parse(header: "bytes=-5", size: 0), .invalid)

        // 9. nil or other headers -> none
        XCTAssertEqual(RangeParser.parse(header: nil, size: size), .none)
        XCTAssertEqual(RangeParser.parse(header: "gzip", size: size), .none)
        XCTAssertEqual(RangeParser.parse(header: "characters=0-5", size: size), .none)
    }

    func testEdgeCases() {
        let size: Int64 = 100

        // Suffix range larger than file size -> start clamped to 0
        XCTAssertEqual(RangeParser.parse(header: "bytes=-200", size: size), .partial(start: 0, end: 99))

        // start > end -> invalid
        XCTAssertEqual(RangeParser.parse(header: "bytes=50-20", size: size), .invalid)

        // empty range bytes=- -> invalid
        XCTAssertEqual(RangeParser.parse(header: "bytes=-", size: size), .invalid)

        // whitespace tolerance
        XCTAssertEqual(RangeParser.parse(header: "  bytes= 10 - 20 ", size: size), .partial(start: 10, end: 20))
    }
}
