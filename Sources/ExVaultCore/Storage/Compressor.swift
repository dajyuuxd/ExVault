// Streaming zlib compression and decompression engine backed by Apple Compression framework.

import Foundation
import Compression
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum CompressError: Error, CustomStringConvertible {
    case failed
    case io(Int32)

    public var description: String {
        switch self {
        case .failed:
            return "CompressError: Compression or decompression operation failed"
        case .io(let code):
            return "CompressError: I/O error with errno \(code)"
        }
    }
}

public enum Compressor {
    /// Compresses data read from inFD up to limitInput bytes, streaming compressed blocks into sink.
    public static func compress(
        from inFD: Int32,
        limitInput: Int64?,
        sink: (UnsafeRawBufferPointer) throws -> Void
    ) throws -> (read: Int64, written: Int64) {
        let bufferSize = 64 * 1024
        let inBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { inBuf.deallocate() }
        let outBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { outBuf.deallocate() }

        let dummy = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        defer { dummy.deallocate() }
        var stream = compression_stream(
            dst_ptr: dummy,
            dst_size: 0,
            src_ptr: UnsafePointer(dummy),
            src_size: 0,
            state: nil
        )
        let initStatus = compression_stream_init(&stream, COMPRESSION_STREAM_ENCODE, COMPRESSION_ZLIB)
        guard initStatus == COMPRESSION_STATUS_OK else {
            throw CompressError.failed
        }
        defer { compression_stream_destroy(&stream) }

        var totalRead: Int64 = 0
        var totalWritten: Int64 = 0
        var eof = false

        while true {
            if stream.src_size == 0 && !eof {
                var toRead = bufferSize
                if let limit = limitInput {
                    let remaining = limit - totalRead
                    if remaining <= 0 {
                        eof = true
                        toRead = 0
                    } else {
                        toRead = min(toRead, Int(remaining))
                    }
                }
                if toRead > 0 {
                    let n = try Net.readFully(fd: inFD, into: inBuf, count: toRead)
                    if n == 0 {
                        eof = true
                    } else {
                        totalRead += Int64(n)
                        stream.src_ptr = UnsafePointer(inBuf)
                        stream.src_size = n
                        if let limit = limitInput, totalRead >= limit {
                            eof = true
                        }
                    }
                }
            }

            stream.dst_ptr = outBuf
            stream.dst_size = bufferSize
            let flags: Int32 = eof ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
            let status = compression_stream_process(&stream, flags)

            let produced = bufferSize - stream.dst_size
            if produced > 0 {
                try sink(UnsafeRawBufferPointer(start: outBuf, count: produced))
                totalWritten += Int64(produced)
            }

            if status == COMPRESSION_STATUS_END {
                break
            } else if status == COMPRESSION_STATUS_ERROR {
                throw CompressError.failed
            } else if status == COMPRESSION_STATUS_OK {
                if eof && stream.src_size == 0 && produced == 0 {
                    break
                }
            } else {
                throw CompressError.failed
            }
        }

        return (read: totalRead, written: totalWritten)
    }

    /// Compresses the entire content of inFD and writes all compressed output to outFD.
    public static func compressFile(from inFD: Int32, to outFD: Int32) throws -> (read: Int64, written: Int64) {
        return try compress(from: inFD, limitInput: nil) { rawBuf in
            guard let base = rawBuf.baseAddress else { return }
            try Net.writeFully(fd: outFD, base, count: rawBuf.count)
        }
    }

    /// Decompresses raw DEFLATE data read from inFD, streaming decompressed chunks into sink.
    public static func decompress(
        from inFD: Int32,
        sink: (UnsafeRawBufferPointer) throws -> Void
    ) throws {
        let bufferSize = 64 * 1024
        let inBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { inBuf.deallocate() }
        let outBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { outBuf.deallocate() }

        let dummy = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        defer { dummy.deallocate() }
        var stream = compression_stream(
            dst_ptr: dummy,
            dst_size: 0,
            src_ptr: UnsafePointer(dummy),
            src_size: 0,
            state: nil
        )
        let initStatus = compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
        guard initStatus == COMPRESSION_STATUS_OK else {
            throw CompressError.failed
        }
        defer { compression_stream_destroy(&stream) }

        var eof = false
        var consecutiveStalls = 0

        while true {
            if stream.src_size == 0 && !eof {
                let n = try Net.readFully(fd: inFD, into: inBuf, count: bufferSize)
                if n == 0 {
                    eof = true
                } else {
                    stream.src_ptr = UnsafePointer(inBuf)
                    stream.src_size = n
                }
            }

            let prevSrcSize = stream.src_size
            stream.dst_ptr = outBuf
            stream.dst_size = bufferSize
            let flags: Int32 = eof ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
            let status = compression_stream_process(&stream, flags)

            let produced = bufferSize - stream.dst_size
            if produced > 0 {
                try sink(UnsafeRawBufferPointer(start: outBuf, count: produced))
            }

            if status == COMPRESSION_STATUS_OK {
                if stream.src_size == prevSrcSize && produced == 0 {
                    consecutiveStalls += 1
                    if consecutiveStalls >= 2 {
                        throw CompressError.failed
                    }
                } else {
                    consecutiveStalls = 0
                }
                if eof && stream.src_size == 0 && produced == 0 {
                    break
                }
            } else if status == COMPRESSION_STATUS_END {
                break
            } else if status == COMPRESSION_STATUS_ERROR {
                throw CompressError.failed
            } else {
                throw CompressError.failed
            }
        }
    }

    /// Measures compression ratio of the initial sampleBytes of data. Returns written/read ratio.
    public static func sampleRatio(fd: Int32, sampleBytes: Int) throws -> Double {
        lseek(fd, 0, SEEK_SET)
        var st = stat()
        if fstat(fd, &st) == 0 && st.st_size == 0 {
            return 1.0
        }

        let result = try compress(from: fd, limitInput: Int64(sampleBytes)) { _ in }
        lseek(fd, 0, SEEK_SET)

        if result.read == 0 {
            return 1.0
        }
        return Double(result.written) / Double(result.read)
    }
}
