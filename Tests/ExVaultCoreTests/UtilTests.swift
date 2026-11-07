// Unit tests for utility modules: IDGen, Crc32, NameRules, MimeTypes, Net, Log, and Json.

import XCTest
@testable import ExVaultCore

final class UtilTests: XCTestCase {

    // MARK: - IDGen Tests

    func testIDGenNewID() {
        let id = IDGen.newID()
        XCTAssertEqual(id.count, 24)
        let allowed = CharacterSet(charactersIn: "0123456789abcdef")
        XCTAssertTrue(id.unicodeScalars.allSatisfy { allowed.contains($0) })
    }

    func testIDGenToken() {
        let token = IDGen.token()
        XCTAssertEqual(token.count, 64)
        let allowed = CharacterSet(charactersIn: "0123456789abcdef")
        XCTAssertTrue(token.unicodeScalars.allSatisfy { allowed.contains($0) })
    }

    func testIDGenUniqueness() {
        var set = Set<String>()
        for _ in 0..<1000 {
            let id = IDGen.newID()
            set.insert(id)
        }
        XCTAssertEqual(set.count, 1000)
    }

    // MARK: - Crc32 Tests

    func testCrc32StandardVector() {
        guard let data = "123456789".data(using: .utf8) else {
            XCTFail("Failed to encode string")
            return
        }
        let crc = Crc32.of(data)
        XCTAssertEqual(crc, 0xCBF43926)
    }

    func testCrc32StreamingUpdate() {
        guard let part1 = "12345".data(using: .utf8),
              let part2 = "6789".data(using: .utf8),
              let full = "123456789".data(using: .utf8) else {
            XCTFail("Failed to encode strings")
            return
        }
        let fullCrc = Crc32.of(full)
        let c1 = Crc32.update(0, part1)
        let c2 = Crc32.update(c1, part2)
        XCTAssertEqual(c2, fullCrc)
    }

    // MARK: - NameRules Tests

    func testNameRulesValidation() {
        XCTAssertNil(NameRules.validate(""))
        XCTAssertNil(NameRules.validate("   "))
        XCTAssertNil(NameRules.validate("."))
        XCTAssertNil(NameRules.validate(".."))
        XCTAssertNil(NameRules.validate("folder/file"))
        XCTAssertNil(NameRules.validate("folder\\file"))
        XCTAssertNil(NameRules.validate("file\u{0000}name"))
        XCTAssertNil(NameRules.validate("file\u{001F}name"))
        XCTAssertNil(NameRules.validate("file\u{007F}name"))

        let longName = String(repeating: "a", count: 256)
        XCTAssertNil(NameRules.validate(longName))

        let exact255 = String(repeating: "a", count: 255)
        XCTAssertEqual(NameRules.validate(exact255), exact255)

        XCTAssertEqual(NameRules.validate("  valid-name.txt  "), "valid-name.txt")
        XCTAssertEqual(NameRules.validate("tài liệu 📁.pdf"), "tài liệu 📁.pdf")
    }

    func testNameRulesSplitExt() {
        let (stem1, ext1) = NameRules.splitExt("a.txt")
        XCTAssertEqual(stem1, "a")
        XCTAssertEqual(ext1, "txt")

        let (stem2, ext2) = NameRules.splitExt(".bashrc")
        XCTAssertEqual(stem2, ".bashrc")
        XCTAssertEqual(ext2, "")

        let (stem3, ext3) = NameRules.splitExt("archive.tar.gz")
        XCTAssertEqual(stem3, "archive.tar")
        XCTAssertEqual(ext3, "gz")

        let (stem4, ext4) = NameRules.splitExt("documents")
        XCTAssertEqual(stem4, "documents")
        XCTAssertEqual(ext4, "")

        let (stem5, ext5) = NameRules.splitExt(".hidden.conf")
        XCTAssertEqual(stem5, ".hidden")
        XCTAssertEqual(ext5, "conf")
    }

    func testNameRulesUniqueName() {
        let existing = Set(["a.txt", "a (1).txt", "docs", ".bashrc"])

        let unique1 = NameRules.uniqueName("new.txt") { existing.contains($0) }
        XCTAssertEqual(unique1, "new.txt")

        let unique2 = NameRules.uniqueName("a.txt") { existing.contains($0) }
        XCTAssertEqual(unique2, "a (2).txt")

        let unique3 = NameRules.uniqueName("docs") { existing.contains($0) }
        XCTAssertEqual(unique3, "docs (1)")

        let unique4 = NameRules.uniqueName(".bashrc") { existing.contains($0) }
        XCTAssertEqual(unique4, ".bashrc (1)")
    }

    // MARK: - MimeTypes & CompressionPolicy Tests

    func testMimeTypesLookup() {
        XCTAssertEqual(MimeTypes.mime(forName: "index.html"), "text/html")
        XCTAssertEqual(MimeTypes.mime(forName: "style.css"), "text/css")
        XCTAssertEqual(MimeTypes.mime(forName: "app.js"), "application/javascript")
        XCTAssertEqual(MimeTypes.mime(forName: "data.json"), "application/json")
        XCTAssertEqual(MimeTypes.mime(forName: "photo.jpg"), "image/jpeg")
        XCTAssertEqual(MimeTypes.mime(forName: "clip.mp4"), "video/mp4")
        XCTAssertEqual(MimeTypes.mime(forName: "clip.m4v"), "video/mp4")
        XCTAssertEqual(MimeTypes.mime(forName: "clip.3gp"), "video/3gpp")
        XCTAssertEqual(MimeTypes.mime(forName: "song.mp3"), "audio/mpeg")
        XCTAssertEqual(MimeTypes.mime(forName: "doc.pdf"), "application/pdf")
        XCTAssertEqual(MimeTypes.mime(forName: "file.unknownext"), "application/octet-stream")
    }

    func testMimeContentTypeCharset() {
        XCTAssertEqual(MimeTypes.contentType(forName: "notes.txt"), "text/plain; charset=utf-8")
        XCTAssertEqual(MimeTypes.contentType(forName: "data.json"), "application/json; charset=utf-8")
        XCTAssertEqual(MimeTypes.contentType(forName: "photo.png"), "image/png")
    }

    func testCompressionPolicyDecision() {
        XCTAssertEqual(CompressionPolicy.decide(name: "short.txt", size: 500), .never)
        XCTAssertEqual(CompressionPolicy.decide(name: "video.mp4", size: 2_000_000), .never)
        XCTAssertEqual(CompressionPolicy.decide(name: "stream.ts", size: 5_000_000), .never)
        XCTAssertEqual(CompressionPolicy.decide(name: "photo.jpg", size: 100_000), .never)
        XCTAssertEqual(CompressionPolicy.decide(name: "source.swift", size: 10_000), .always)
        XCTAssertEqual(CompressionPolicy.decide(name: "log.txt", size: 5_000), .always)
        XCTAssertEqual(CompressionPolicy.decide(name: "archive.pdf", size: 50_000), .sample)
        XCTAssertEqual(CompressionPolicy.decide(name: "custom.bin", size: 50_000), .sample)
    }

    // MARK: - Net Tests

    func testConstantTimeEquals() {
        XCTAssertTrue(Net.constantTimeEquals("secret123", "secret123"))
        XCTAssertFalse(Net.constantTimeEquals("secret123", "secret124"))
        XCTAssertFalse(Net.constantTimeEquals("short", "longer_string"))
        XCTAssertFalse(Net.constantTimeEquals("", "nonempty"))
        XCTAssertTrue(Net.constantTimeEquals("", ""))
    }

    func testPercentDecode() {
        XCTAssertEqual(Net.percentDecode("%E1%BB%91"), "ố")
        XCTAssertEqual(Net.percentDecode("hello%20world"), "hello world")
        XCTAssertEqual(Net.percentDecode("plain"), "plain")
    }

    func testParseQuery() {
        let q1 = Net.parseQuery("a=1&b=2&c=hello+world")
        XCTAssertEqual(q1["a"], "1")
        XCTAssertEqual(q1["b"], "2")
        XCTAssertEqual(q1["c"], "hello world")

        let q2 = Net.parseQuery("name=alice&name=bob")
        XCTAssertEqual(q2["name"], "bob")

        let q3 = Net.parseQuery("")
        XCTAssertTrue(q3.isEmpty)

        let q4 = Net.parseQuery("flag&key=val")
        XCTAssertEqual(q4["flag"], "")
        XCTAssertEqual(q4["key"], "val")
    }

    func testNetHex() {
        let data = Data([0x00, 0x01, 0x0a, 0xfe, 0xff])
        XCTAssertEqual(Net.hex(data), "00010afeff")
    }

    // MARK: - Log Tests

    func testLogSinkAndBuffer() {
        Log.clear()
        var received: String?
        Log.sink = { line in
            received = line
        }

        Log.info("Test info message")
        XCTAssertNotNil(received)
        guard let line = received else {
            XCTFail("Sink did not receive line")
            return
        }
        XCTAssertTrue(line.contains("[I] Test info message"))

        Log.warn("Test warn message")
        Log.error("Test error message")

        let lines = Log.recentLines()
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].contains("[I]"))
        XCTAssertTrue(lines[1].contains("[W]"))
        XCTAssertTrue(lines[2].contains("[E]"))

        let last2 = Log.recentLines(2)
        XCTAssertEqual(last2.count, 2)
        XCTAssertTrue(last2[0].contains("[W]"))
        XCTAssertTrue(last2[1].contains("[E]"))
        Log.sink = nil
    }

    // MARK: - Json Tests

    struct SampleModel: Codable, Equatable {
        let name: String
        let count: Int
    }

    func testJsonEncodeDecode() throws {
        let original = SampleModel(name: "ExVault", count: 42)
        let data = try Json.encode(original)
        let decoded = try Json.decode(SampleModel.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testJsonObjectAndDictionary() throws {
        let dict: [String: Any] = ["status": "ok", "code": 200]
        let data = try Json.object(dict)
        let parsed = try Json.toDictionary(data)
        XCTAssertEqual(parsed["status"] as? String, "ok")
        XCTAssertEqual(parsed["code"] as? Int, 200)
    }
}
