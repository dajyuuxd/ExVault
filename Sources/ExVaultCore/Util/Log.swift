// In-memory ring buffer logger with thread-safe UI subscription and console output.

import Foundation

public enum Log {
    public static var sink: ((String) -> Void)?

    private static let lock = NSLock()
    private static var buffer: [String] = []
    private static let maxLines = 200

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    public static func info(_ msg: String) {
        log(level: "I", message: msg)
    }

    public static func warn(_ msg: String) {
        log(level: "W", message: msg)
    }

    public static func error(_ msg: String) {
        log(level: "E", message: msg)
    }

    private static func log(level: String, message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let line = "\(timestamp) [\(level)] \(message)"

        print(line)

        lock.lock()
        buffer.append(line)
        if buffer.count > maxLines {
            buffer.removeFirst(buffer.count - maxLines)
        }
        let currentSink = sink
        lock.unlock()

        currentSink?(line)
    }

    /// Returns a copy of the most recent log lines (up to 200 entries).
    public static func recentLines() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    /// Clears the in-memory log buffer.
    public static func clear() {
        lock.lock()
        defer { lock.unlock() }
        buffer.removeAll()
    }
}
