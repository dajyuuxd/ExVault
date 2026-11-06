# T02 — SQLite wrapper + schema

**Đọc**: `docs/02` mục 1, `docs/01` mục 5–6.

## File: `Storage/Database.swift`, `Storage/Schema.swift`
```swift
import SQLite3
enum SQLValue { case int(Int64), text(String), null }
struct Row {
    func int(_ col: Int32) -> Int64
    func text(_ col: Int32) -> String          // NULL ⇒ ""
    func optText(_ col: Int32) -> String?
    func optInt(_ col: Int32) -> Int64?
    func isNull(_ col: Int32) -> Bool
}
final class Database {
    init(path: String) throws                   // mở FULLMUTEX, PRAGMA, migrate
    deinit                                      // sqlite3_close
    func exec(_ sql: String) throws             // không tham số
    @discardableResult func run(_ sql: String, _ binds: [SQLValue] = []) throws -> Int   // trả sqlite3_changes
    func query<T>(_ sql: String, _ binds: [SQLValue] = [], _ map: (Row) -> T) throws -> [T]
    func scalarInt(_ sql: String, _ binds: [SQLValue] = []) throws -> Int64?
    var lastInsertRowID: Int64 { get }
    func transaction<T>(_ body: () throws -> T) throws -> T    // BEGIN IMMEDIATE / COMMIT / ROLLBACK khi ném lỗi
    let queue: DispatchQueue                    // serial "exv.db"
    func sync<T>(_ body: () throws -> T) rethrows -> T          // queue.sync
}
struct DBError: Error { let code: Int32; let message: String }
```
- `let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)` khi `sqlite3_bind_text`.
- `query`: `sqlite3_prepare_v2` → bind → `while sqlite3_step == SQLITE_ROW { map(Row(stmt)) }` → `sqlite3_finalize` (dùng `defer`). Lỗi ⇒ `DBError` kèm `sqlite3_errmsg`.
- `transaction` lồng nhau: dùng bộ đếm độ sâu; chỉ lớp ngoài cùng BEGIN/COMMIT.
- `Schema.swift`: `static let v1: [String]` chứa các câu `CREATE` đúng `docs/02`; `migrate(db)` đọc `PRAGMA user_version`, nếu 0 thì chạy trong transaction rồi `PRAGMA user_version=1`.
- Quy ước: **các lớp trên gọi `db.sync { … }` quanh mỗi thao tác kho**; bản thân `run/query` không tự `sync`.

## Test: `DatabaseTests.swift` (file DB tạm)
Tạo schema; insert/select; bind text có dấu nháy `'` và emoji; NULL; transaction rollback khi ném lỗi; foreign key cascade (xóa node cha xóa node con và `node_tags`); user_version=1 sau migrate; mở lại file không migrate lần hai.

## Nghiệm thu
- [ ] `swift test` xanh. [ ] Không ghép chuỗi SQL từ giá trị biến (trừ danh sách `?,?,?` sinh theo số lượng).
