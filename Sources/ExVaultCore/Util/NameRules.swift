// Node naming validation, extension splitting, and collision avoidance rules.

import Foundation

public enum NameRules {
    /// Validates a raw name input. Trims whitespace and checks against invalid patterns.
    public static func validate(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }
        if trimmed == "." || trimmed == ".." {
            return nil
        }
        if trimmed.contains("/") || trimmed.contains("\\") {
            return nil
        }
        for scalar in trimmed.unicodeScalars {
            if scalar.value <= 0x1F || scalar.value == 0x7F {
                return nil
            }
        }
        if trimmed.utf8.count > 255 {
            return nil
        }
        return trimmed
    }

    /// Splits a file or folder name into its stem and extension. Extension does not include the leading dot.
    public static func splitExt(_ name: String) -> (stem: String, ext: String) {
        guard let lastDotIndex = name.lastIndex(of: ".") else {
            return (stem: name, ext: "")
        }

        // If the dot is at the very beginning and there is no other dot, treat as hidden file with no extension
        if lastDotIndex == name.startIndex {
            return (stem: name, ext: "")
        }

        let stem = String(name[..<lastDotIndex])
        let ext = String(name[name.index(after: lastDotIndex)...])
        return (stem: stem, ext: ext)
    }

    /// Generates a unique name within the same container using standard numbering suffixes.
    public static func uniqueName(_ base: String, exists: (String) -> Bool) -> String {
        if !exists(base) {
            return base
        }

        let (stem, ext) = splitExt(base)
        for i in 1...10000 {
            let candidate: String
            if ext.isEmpty {
                candidate = "\(stem) (\(i))"
            } else {
                candidate = "\(stem) (\(i)).\(ext)"
            }
            if !exists(candidate) {
                return candidate
            }
        }

        // Fatal-free fallback: append 8 random hex characters
        let suffix = String(IDGen.newID().prefix(8))
        if ext.isEmpty {
            return "\(stem)-\(suffix)"
        } else {
            return "\(stem)-\(suffix).\(ext)"
        }
    }
}
