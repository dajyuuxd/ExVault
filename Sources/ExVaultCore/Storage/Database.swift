// SQLite database wrapper with thread synchronization, prepared statements, and transaction management.

import Foundation
import SQLite3

public enum SQLValue {
    case int(Int64)
    case text(String)
    case null
}

public struct Row {
    private let stmt: OpaquePointer

    init(_ stmt: OpaquePointer) {
        self.stmt = stmt
    }

    public func int(_ col: Int32) -> Int64 {
        return sqlite3_column_int64(stmt, col)
    }

    public func text(_ col: Int32) -> String {
        guard let cStr = sqlite3_column_text(stmt, col) else {
            return ""
        }
        return String(cString: cStr)
    }

    public func optText(_ col: Int32) -> String? {
        if isNull(col) {
            return nil
        }
        guard let cStr = sqlite3_column_text(stmt, col) else {
            return nil
        }
        return String(cString: cStr)
    }

    public func optInt(_ col: Int32) -> Int64? {
        if isNull(col) {
            return nil
        }
        return sqlite3_column_int64(stmt, col)
    }

    public func isNull(_ col: Int32) -> Bool {
        return sqlite3_column_type(stmt, col) == SQLITE_NULL
    }
}

public struct DBError: Error, CustomStringConvertible {
    public let code: Int32
    public let message: String

    public var description: String {
        return "DBError(code: \(code), message: \(message))"
    }
}

public final class Database {
    private var handle: OpaquePointer?
    public let queue = DispatchQueue(label: "exv.db")
    private var transactionDepth: Int = 0

    private static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(path: String) throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &db, flags, nil)
        if rc != SQLITE_OK {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Failed to open database"
            if let db = db {
                sqlite3_close(db)
            }
            throw DBError(code: rc, message: msg)
        }
        self.handle = db

        // Configure connection pragmas for performance and data integrity
        try exec("PRAGMA journal_mode=WAL;")
        try exec("PRAGMA synchronous=NORMAL;")
        try exec("PRAGMA foreign_keys=ON;")
        try exec("PRAGMA cache_size=-2000;")
        try exec("PRAGMA mmap_size=0;")
        try exec("PRAGMA temp_store=FILE;")

        try Schema.migrate(self)
    }

    deinit {
        if let h = handle {
            sqlite3_close(h)
        }
    }

    private func makeError(code: Int32) -> DBError {
        let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
        return DBError(code: code, message: msg)
    }

    public func exec(_ sql: String) throws {
        guard let h = handle else {
            throw DBError(code: SQLITE_MISUSE, message: "Database is closed")
        }
        let rc = sqlite3_exec(h, sql, nil, nil, nil)
        if rc != SQLITE_OK {
            throw makeError(code: rc)
        }
    }

    @discardableResult
    public func run(_ sql: String, _ binds: [SQLValue] = []) throws -> Int {
        guard let h = handle else {
            throw DBError(code: SQLITE_MISUSE, message: "Database is closed")
        }
        var stmt: OpaquePointer?
        let prepRc = sqlite3_prepare_v2(h, sql, -1, &stmt, nil)
        if prepRc != SQLITE_OK {
            throw makeError(code: prepRc)
        }
        guard let s = stmt else {
            throw DBError(code: SQLITE_ERROR, message: "Prepared statement is null")
        }
        defer { sqlite3_finalize(s) }

        try bindValues(s, binds)

        let stepRc = sqlite3_step(s)
        if stepRc != SQLITE_DONE && stepRc != SQLITE_ROW {
            throw makeError(code: stepRc)
        }
        return Int(sqlite3_changes(h))
    }

    public func query<T>(_ sql: String, _ binds: [SQLValue] = [], _ map: (Row) -> T) throws -> [T] {
        guard let h = handle else {
            throw DBError(code: SQLITE_MISUSE, message: "Database is closed")
        }
        var stmt: OpaquePointer?
        let prepRc = sqlite3_prepare_v2(h, sql, -1, &stmt, nil)
        if prepRc != SQLITE_OK {
            throw makeError(code: prepRc)
        }
        guard let s = stmt else {
            throw DBError(code: SQLITE_ERROR, message: "Prepared statement is null")
        }
        defer { sqlite3_finalize(s) }

        try bindValues(s, binds)

        var results: [T] = []
        let row = Row(s)
        while true {
            let stepRc = sqlite3_step(s)
            if stepRc == SQLITE_ROW {
                results.append(map(row))
            } else if stepRc == SQLITE_DONE {
                break
            } else {
                throw makeError(code: stepRc)
            }
        }
        return results
    }

    public func scalarInt(_ sql: String, _ binds: [SQLValue] = []) throws -> Int64? {
        let rows = try query(sql, binds) { row in
            row.isNull(0) ? nil : row.int(0)
        }
        return rows.first ?? nil
    }

    public var lastInsertRowID: Int64 {
        guard let h = handle else { return 0 }
        return sqlite3_last_insert_rowid(h)
    }

    public func transaction<T>(_ body: () throws -> T) throws -> T {
        if transactionDepth == 0 {
            try exec("BEGIN IMMEDIATE;")
        }
        transactionDepth += 1
        do {
            let result = try body()
            transactionDepth -= 1
            if transactionDepth == 0 {
                try exec("COMMIT;")
            }
            return result
        } catch {
            transactionDepth -= 1
            if transactionDepth == 0 {
                _ = try? exec("ROLLBACK;")
            }
            throw error
        }
    }

    public func sync<T>(_ body: () throws -> T) rethrows -> T {
        return try queue.sync(execute: body)
    }

    private func bindValues(_ stmt: OpaquePointer, _ binds: [SQLValue]) throws {
        for (index, val) in binds.enumerated() {
            let col = Int32(index + 1)
            let rc: Int32
            switch val {
            case .int(let v):
                rc = sqlite3_bind_int64(stmt, col, v)
            case .text(let s):
                rc = sqlite3_bind_text(stmt, col, s, -1, Database.SQLITE_TRANSIENT)
            case .null:
                rc = sqlite3_bind_null(stmt, col)
            }
            if rc != SQLITE_OK {
                throw makeError(code: rc)
            }
        }
    }
}
