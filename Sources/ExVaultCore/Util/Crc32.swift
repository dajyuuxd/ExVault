// Standard CRC32 implementation using polynomial 0xEDB88320 with streaming support.

import Foundation

public enum Crc32 {
    private static let table: [UInt32] = {
        var tbl = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 {
                if c & 1 != 0 {
                    c = 0xEDB88320 ^ (c >> 1)
                } else {
                    c >>= 1
                }
            }
            tbl[i] = c
        }
        return tbl
    }()

    /// Incrementally updates a CRC32 checksum with raw bytes.
    public static func update(_ crc: UInt32, _ buf: UnsafeRawBufferPointer) -> UInt32 {
        var c = ~crc
        for byte in buf {
            let idx = Int((c ^ UInt32(byte)) & 0xFF)
            c = table[idx] ^ (c >> 8)
        }
        return ~c
    }

    /// Incrementally updates a CRC32 checksum with Data.
    public static func update(_ crc: UInt32, _ data: Data) -> UInt32 {
        return data.withUnsafeBytes { rawBuffer in
            update(crc, rawBuffer)
        }
    }

    /// Computes CRC32 for an entire Data object.
    public static func of(_ data: Data) -> UInt32 {
        return update(0, data)
    }
}
