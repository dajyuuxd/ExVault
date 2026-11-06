// POSIX socket helpers, constant-time comparison, URL decoding, and interface discovery.

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum Net {
    /// Reads up to count bytes into buf from fd. Returns total bytes read (0 indicates EOF).
    public static func readFully(fd: Int32, into buf: UnsafeMutableRawPointer, count: Int) throws -> Int {
        var totalRead = 0
        var ptr = buf
        while totalRead < count {
            let remaining = count - totalRead
            let n = read(fd, ptr, remaining)
            if n > 0 {
                totalRead += n
                ptr = ptr.advanced(by: n)
            } else if n == 0 {
                break
            } else {
                let err = errno
                if err == EINTR {
                    continue
                }
                throw POSIXError(POSIXErrorCode(rawValue: err) ?? .EIO)
            }
        }
        return totalRead
    }

    /// Writes all count bytes from buf to fd, retrying on EINTR.
    public static func writeFully(fd: Int32, _ buf: UnsafeRawPointer, count: Int) throws {
        var totalWritten = 0
        var ptr = buf
        while totalWritten < count {
            let remaining = count - totalWritten
            let n = write(fd, ptr, remaining)
            if n > 0 {
                totalWritten += n
                ptr = ptr.advanced(by: n)
            } else {
                let err = errno
                if err == EINTR {
                    continue
                }
                throw POSIXError(POSIXErrorCode(rawValue: err) ?? .EIO)
            }
        }
    }

    /// Constant-time string equality check to mitigate timing side-channel attacks.
    public static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        let maxLen = max(aBytes.count, bBytes.count)
        var diff = aBytes.count ^ bBytes.count
        for i in 0..<maxLen {
            let byteA = i < aBytes.count ? Int(aBytes[i]) : 0
            let byteB = i < bBytes.count ? Int(bBytes[i]) : 0
            diff |= (byteA ^ byteB)
        }
        return diff == 0
    }

    /// Percent-decodes a UTF-8 percent-encoded string. Returns nil if the sequence is invalid.
    public static func percentDecode(_ s: String) -> String? {
        return s.removingPercentEncoding
    }

    /// Parses URL query parameters, replacing '+' with space and decoding keys/values.
    /// Duplicate keys retain the last encountered value.
    public static func parseQuery(_ s: String) -> [String: String] {
        if s.isEmpty {
            return [:]
        }
        var result: [String: String] = [:]
        let pairs = s.split(separator: "&", omittingEmptySubsequences: true)
        for pair in pairs {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let rawKey = String(parts[0]).replacingOccurrences(of: "+", with: " ")
            let rawVal = parts.count > 1 ? String(parts[1]).replacingOccurrences(of: "+", with: " ") : ""
            let key = percentDecode(rawKey) ?? rawKey
            let val = percentDecode(rawVal) ?? rawVal
            result[key] = val
        }
        return result
    }

    /// Discovers active local IPv4 addresses on en* and bridge* network interfaces.
    public static func localIPv4Addresses() -> [String] {
        var addresses: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return []
        }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }
            let ifa = current.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }
            let name = String(cString: ifa.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("bridge") else {
                continue
            }
            var ip = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var sin = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            if inet_ntop(AF_INET, &sin.sin_addr, &ip, socklen_t(INET_ADDRSTRLEN)) != nil {
                let ipStr = String(cString: ip)
                if !ipStr.hasPrefix("127.") && !ipStr.hasPrefix("169.254.") {
                    if !addresses.contains(ipStr) {
                        addresses.append(ipStr)
                    }
                }
            }
        }
        return addresses
    }

    /// Converts raw data into a lowercase hexadecimal string.
    public static func hex(_ data: Data) -> String {
        return data.map { String(format: "%02x", $0) }.joined()
    }
}
