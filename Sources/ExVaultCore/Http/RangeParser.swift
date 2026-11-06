// HTTP Range header parser supporting single byte ranges and suffix ranges.

import Foundation

public enum RangeResult: Equatable {
    case none
    case full
    case partial(start: Int64, end: Int64)
    case invalid
}

public enum RangeParser {
    public static func parse(header: String?, size: Int64) -> RangeResult {
        guard let rawHeader = header?.trimmingCharacters(in: .whitespaces),
              rawHeader.hasPrefix("bytes=") else {
            return .none
        }

        let rangeSpec = String(rawHeader.dropFirst("bytes=".count)).trimmingCharacters(in: .whitespaces)

        // Multiple ranges (contain comma) -> return .none per spec
        if rangeSpec.contains(",") {
            return .none
        }

        // Any Range request on empty file -> .invalid per spec
        if size <= 0 {
            return .invalid
        }

        guard let dashIndex = rangeSpec.firstIndex(of: "-") else {
            return .invalid
        }

        let firstPart = String(rangeSpec[..<dashIndex]).trimmingCharacters(in: .whitespaces)
        let secondPart = String(rangeSpec[rangeSpec.index(after: dashIndex)...]).trimmingCharacters(in: .whitespaces)

        if firstPart.isEmpty && secondPart.isEmpty {
            return .invalid
        }

        // Suffix range: "-n"
        if firstPart.isEmpty {
            guard let n = Int64(secondPart), n > 0 else {
                return .invalid
            }
            let start = max(0, size - n)
            return .partial(start: start, end: size - 1)
        }

        guard let start = Int64(firstPart), start >= 0 else {
            return .invalid
        }

        if start >= size {
            return .invalid
        }

        // Prefix range: "a-"
        if secondPart.isEmpty {
            return .partial(start: start, end: size - 1)
        }

        // Range "a-b"
        guard let endVal = Int64(secondPart), endVal >= 0 else {
            return .invalid
        }

        if start > endVal {
            return .invalid
        }

        let clampedEnd = min(endVal, size - 1)
        return .partial(start: start, end: clampedEnd)
    }
}
