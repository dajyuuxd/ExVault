import XCTest
@testable import ExVaultCore

final class SilentWavTests: XCTestCase {
    func testMakeOneSecond() {
        let wav = SilentWav.make(seconds: 1)
        XCTAssertEqual(wav.count, 44 + 16000)

        // Check RIFF
        let riff = String(data: wav.subdata(in: 0..<4), encoding: .ascii)
        XCTAssertEqual(riff, "RIFF")

        // Check WAVE
        let wave = String(data: wav.subdata(in: 8..<12), encoding: .ascii)
        XCTAssertEqual(wave, "WAVE")

        // Check fmt
        let fmt = String(data: wav.subdata(in: 12..<16), encoding: .ascii)
        XCTAssertEqual(fmt, "fmt ")

        // Check data
        let dataTag = String(data: wav.subdata(in: 36..<40), encoding: .ascii)
        XCTAssertEqual(dataTag, "data")

        // Check data size field (offset 40..<44)
        let dataSize = UInt32(wav[40]) | (UInt32(wav[41]) << 8) | (UInt32(wav[42]) << 16) | (UInt32(wav[43]) << 24)
        XCTAssertEqual(dataSize, 16000)

        // Check that all sample bytes are 0
        let samples = wav.subdata(in: 44..<wav.count)
        for b in samples {
            XCTAssertEqual(b, 0)
        }
    }

    func testMakeMultipleSeconds() {
        let wav = SilentWav.make(seconds: 3)
        XCTAssertEqual(wav.count, 44 + 48000)

        let dataSize = UInt32(wav[40]) | (UInt32(wav[41]) << 8) | (UInt32(wav[42]) << 16) | (UInt32(wav[43]) << 24)
        XCTAssertEqual(dataSize, 48000)
    }
}
