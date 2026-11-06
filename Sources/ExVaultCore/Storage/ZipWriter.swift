// Streaming ZIP archive writer using stored (uncompressed) entries and standard PKZIP format.

import Foundation

public struct ZipEntry {
    public let path: String
    public let isDir: Bool
    public let size: Int64
    public let crc32: UInt32
    public let node: Node?

    public init(path: String, isDir: Bool, size: Int64, crc32: UInt32, node: Node? = nil) {
        self.path = path
        self.isDir = isDir
        self.size = size
        self.crc32 = crc32
        self.node = node
    }
}

public final class ZipWriter {
    public let entries: [ZipEntry]

    public init(entries: [ZipEntry]) {
        self.entries = entries
    }

    /// Calculates the total exact archive length in bytes according to ZIP specification.
    /// totalLength = Σ(30 + nameLen + size) + Σ(46 + nameLen) + 22
    public static func totalLength(entries: [ZipEntry]) -> Int64 {
        var total: Int64 = 0
        // Local file headers + file data
        for entry in entries {
            let nameLen = Int64(entry.path.utf8.count)
            let dataLen = entry.isDir ? 0 : entry.size
            total += 30 + nameLen + dataLen
        }
        // Central directory headers
        for entry in entries {
            let nameLen = Int64(entry.path.utf8.count)
            total += 46 + nameLen
        }
        // End of central directory record
        total += 22
        return total
    }

    public static func dosDateTime(from timestamp: Int64?) -> (time: UInt16, date: UInt16) {
        guard let ts = timestamp, ts > 0 else {
            return (0x0000, 0x0021)
        }
        let seconds = ts > 1_000_000_000_000 ? (ts / 1000) : ts
        let date = Date(timeIntervalSince1970: TimeInterval(seconds))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard let year = c.year, year >= 1980, year <= 2107,
              let month = c.month, let day = c.day,
              let hour = c.hour, let min = c.minute, let sec = c.second else {
            return (0x0000, 0x0021)
        }
        let dosTime = UInt16((hour << 11) | (min << 5) | (sec / 2))
        let dosDate = UInt16(((year - 1980) << 9) | (month << 5) | day)
        return (dosTime, dosDate)
    }

    public static func appendLE16(_ val: UInt16, to data: inout Data) {
        var le = val.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    public static func appendLE32(_ val: UInt32, to data: inout Data) {
        var le = val.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    /// Streams the ZIP archive to writer, retrieving uncompressed data for files via openData.
    public func write(
        to writer: ResponseWriter,
        openData: (ZipEntry, (UnsafeRawBufferPointer) throws -> Void) throws -> Void
    ) throws {
        var localHeaderOffsets: [UInt32] = []
        var currentOffset: Int64 = 0

        // 1. Write Local File Headers + File Data
        for entry in entries {
            let nameBytes = Array(entry.path.utf8)
            let (dosTime, dosDate) = ZipWriter.dosDateTime(from: entry.node?.modifiedAt)

            localHeaderOffsets.append(UInt32(currentOffset))

            var localHeader = Data()
            localHeader.reserveCapacity(30 + nameBytes.count)

            // Signature 0x04034B50
            ZipWriter.appendLE32(0x04034B50, to: &localHeader)
            // Version needed to extract: 20
            ZipWriter.appendLE16(20, to: &localHeader)
            // General purpose bit flag: 0x0800 (bit 11 set for UTF-8)
            ZipWriter.appendLE16(0x0800, to: &localHeader)
            // Compression method: 0 (stored)
            ZipWriter.appendLE16(0, to: &localHeader)
            // Mod time & date
            ZipWriter.appendLE16(dosTime, to: &localHeader)
            ZipWriter.appendLE16(dosDate, to: &localHeader)
            // CRC-32
            ZipWriter.appendLE32(entry.isDir ? 0 : entry.crc32, to: &localHeader)
            // Compressed size
            ZipWriter.appendLE32(entry.isDir ? 0 : UInt32(entry.size), to: &localHeader)
            // Uncompressed size
            ZipWriter.appendLE32(entry.isDir ? 0 : UInt32(entry.size), to: &localHeader)
            // Filename length
            ZipWriter.appendLE16(UInt16(nameBytes.count), to: &localHeader)
            // Extra field length: 0
            ZipWriter.appendLE16(0, to: &localHeader)
            // Filename
            localHeader.append(contentsOf: nameBytes)

            try writer.write(localHeader)
            currentOffset += Int64(localHeader.count)

            if !entry.isDir && entry.size > 0 {
                try openData(entry) { chunk in
                    guard chunk.count > 0 else { return }
                    try writer.write(chunk)
                }
                currentOffset += entry.size
            }
        }

        // 2. Write Central Directory Headers
        let cdStartOffset = currentOffset
        for (i, entry) in entries.enumerated() {
            let nameBytes = Array(entry.path.utf8)
            let (dosTime, dosDate) = ZipWriter.dosDateTime(from: entry.node?.modifiedAt)

            var cdHeader = Data()
            cdHeader.reserveCapacity(46 + nameBytes.count)

            // Signature 0x02014B50
            ZipWriter.appendLE32(0x02014B50, to: &cdHeader)
            // Version made by: 20
            ZipWriter.appendLE16(20, to: &cdHeader)
            // Version needed to extract: 20
            ZipWriter.appendLE16(20, to: &cdHeader)
            // General purpose bit flag: 0x0800
            ZipWriter.appendLE16(0x0800, to: &cdHeader)
            // Compression method: 0
            ZipWriter.appendLE16(0, to: &cdHeader)
            // Mod time & date
            ZipWriter.appendLE16(dosTime, to: &cdHeader)
            ZipWriter.appendLE16(dosDate, to: &cdHeader)
            // CRC-32
            ZipWriter.appendLE32(entry.isDir ? 0 : entry.crc32, to: &cdHeader)
            // Compressed size
            ZipWriter.appendLE32(entry.isDir ? 0 : UInt32(entry.size), to: &cdHeader)
            // Uncompressed size
            ZipWriter.appendLE32(entry.isDir ? 0 : UInt32(entry.size), to: &cdHeader)
            // Filename length
            ZipWriter.appendLE16(UInt16(nameBytes.count), to: &cdHeader)
            // Extra field length: 0
            ZipWriter.appendLE16(0, to: &cdHeader)
            // File comment length: 0
            ZipWriter.appendLE16(0, to: &cdHeader)
            // Disk number start: 0
            ZipWriter.appendLE16(0, to: &cdHeader)
            // Internal file attributes: 0
            ZipWriter.appendLE16(0, to: &cdHeader)
            // External file attributes: 0x10 if isDir else 0
            ZipWriter.appendLE32(entry.isDir ? 0x00000010 : 0, to: &cdHeader)
            // Relative offset of local header
            ZipWriter.appendLE32(localHeaderOffsets[i], to: &cdHeader)
            // Filename
            cdHeader.append(contentsOf: nameBytes)

            try writer.write(cdHeader)
            currentOffset += Int64(cdHeader.count)
        }
        let cdSize = currentOffset - cdStartOffset

        // 3. Write End of Central Directory Record (EOCD)
        var eocd = Data()
        eocd.reserveCapacity(22)

        // Signature 0x06054B50
        ZipWriter.appendLE32(0x06054B50, to: &eocd)
        // Number of this disk: 0
        ZipWriter.appendLE16(0, to: &eocd)
        // Disk where central directory starts: 0
        ZipWriter.appendLE16(0, to: &eocd)
        // Number of central directory records on this disk
        ZipWriter.appendLE16(UInt16(entries.count), to: &eocd)
        // Total number of central directory records
        ZipWriter.appendLE16(UInt16(entries.count), to: &eocd)
        // Size of central directory
        ZipWriter.appendLE32(UInt32(cdSize), to: &eocd)
        // Offset of start of central directory
        ZipWriter.appendLE32(UInt32(cdStartOffset), to: &eocd)
        // ZIP comment length: 0
        ZipWriter.appendLE16(0, to: &eocd)

        try writer.write(eocd)
    }
}
