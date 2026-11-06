// MIME type lookup and compression policy classification based on file extensions.

import Foundation

public enum CompressionDecision {
    case never
    case always
    case sample
}

public enum CompressionPolicy {
    public static let neverExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "avif",
        "mp4", "m4v", "mov", "mkv", "avi", "webm", "wmv", "flv",
        "mp3", "aac", "m4a", "flac", "ogg", "opus", "wma",
        "zip", "rar", "7z", "gz", "bz2", "xz", "zst", "tgz", "lz4",
        "apk", "ipa", "jar", "docx", "xlsx", "pptx", "odt", "ods", "odp", "epub"
    ]

    public static let alwaysExtensions: Set<String> = [
        "txt", "md", "log", "csv", "tsv", "json", "xml", "html", "htm",
        "css", "js", "ts", "svg", "yaml", "yml", "ini", "conf", "sql",
        "srt", "vtt", "bmp", "tif", "tiff", "wav", "raw", "dng", "psd",
        "iso", "vmdk", "tar", "c", "h", "cpp", "java", "py", "swift"
    ]

    /// Decides whether a file should be compressed based on its name and original size.
    public static func decide(name: String, size: Int64) -> CompressionDecision {
        if size < 1024 {
            return .never
        }
        let (_, ext) = NameRules.splitExt(name)
        let lowerExt = ext.lowercased()
        if neverExtensions.contains(lowerExt) {
            return .never
        }
        if alwaysExtensions.contains(lowerExt) {
            return .always
        }
        return .sample
    }
}

public enum MimeTypes {
    private static let mimeTable: [String: String] = [
        "txt": "text/plain",
        "md": "text/markdown",
        "html": "text/html",
        "htm": "text/html",
        "css": "text/css",
        "js": "application/javascript",
        "ts": "application/typescript",
        "json": "application/json",
        "xml": "application/xml",
        "csv": "text/csv",
        "tsv": "text/tab-separated-values",
        "svg": "image/svg+xml",
        "png": "image/png",
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "gif": "image/gif",
        "webp": "image/webp",
        "bmp": "image/bmp",
        "ico": "image/x-icon",
        "heic": "image/heic",
        "heif": "image/heif",
        "avif": "image/avif",
        "tif": "image/tiff",
        "tiff": "image/tiff",
        "mp4": "video/mp4",
        "m4v": "video/x-m4v",
        "mov": "video/quicktime",
        "webm": "video/webm",
        "mkv": "video/x-matroska",
        "avi": "video/x-msvideo",
        "wmv": "video/x-ms-wmv",
        "flv": "video/x-flv",
        "mp3": "audio/mpeg",
        "m4a": "audio/mp4",
        "aac": "audio/aac",
        "wav": "audio/wav",
        "flac": "audio/flac",
        "ogg": "audio/ogg",
        "opus": "audio/opus",
        "wma": "audio/x-ms-wma",
        "pdf": "application/pdf",
        "zip": "application/zip",
        "gz": "application/gzip",
        "tgz": "application/gzip",
        "tar": "application/x-tar",
        "7z": "application/x-7z-compressed",
        "rar": "application/vnd.rar",
        "bz2": "application/x-bzip2",
        "xz": "application/x-xz",
        "zst": "application/zstd",
        "lz4": "application/x-lz4",
        "apk": "application/vnd.android.package-archive",
        "ipa": "application/octet-stream",
        "jar": "application/java-archive",
        "doc": "application/msword",
        "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "xls": "application/vnd.ms-excel",
        "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "ppt": "application/vnd.ms-powerpoint",
        "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        "odt": "application/vnd.oasis.opendocument.text",
        "ods": "application/vnd.oasis.opendocument.spreadsheet",
        "odp": "application/vnd.oasis.opendocument.presentation",
        "epub": "application/epub+zip",
        "sql": "application/sql",
        "yaml": "text/yaml",
        "yml": "text/yaml",
        "ini": "text/plain",
        "conf": "text/plain",
        "log": "text/plain",
        "swift": "text/plain",
        "c": "text/plain",
        "h": "text/plain",
        "cpp": "text/plain",
        "java": "text/plain",
        "py": "text/plain",
        "srt": "text/plain",
        "vtt": "text/vtt"
    ]

    /// Maps a file name or extension to a canonical MIME type string.
    public static func mime(forName name: String) -> String {
        let (_, ext) = NameRules.splitExt(name)
        let key = ext.lowercased()
        return mimeTable[key] ?? "application/octet-stream"
    }

    /// Formats the Content-Type header value with charset if text-based.
    public static func contentType(forName name: String) -> String {
        let baseMime = mime(forName: name)
        if baseMime.hasPrefix("text/") || baseMime == "application/json" || baseMime == "application/xml" || baseMime == "application/javascript" {
            return "\(baseMime); charset=utf-8"
        }
        return baseMime
    }
}
