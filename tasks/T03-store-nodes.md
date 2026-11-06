# T03 — VaultStore (nodes, thùng rác)

**Đọc**: `docs/02` toàn bộ, `docs/03` mục Node.

## File: `Storage/VaultStore.swift`
```swift
struct Node: Codable {
    var id: String; var parentId: String?; var kind: String        // "folder"|"file"
    var name: String; var size: Int64; var storedSize: Int64; var mime: String
    var codec: String                                              // "raw"|"zlib"
    var hasThumb: Bool; var tagIds: [Int64]; var createdAt: Int64; var modifiedAt: Int64; var trashedAt: Int64?
}
enum SortKey: String { case name, size, date, type }
enum SortOrder: String { case asc, desc }
struct StoreError: Error { let code: String; let message: String }   // code ∈ docs/03: not_found, name_conflict, invalid_name, invalid_move

final class VaultStore {
    init(db: Database)
    func getNode(_ id: String) throws -> Node?                     // kể cả trashed
    func listChildren(parentId: String?, sort: SortKey, order: SortOrder) throws -> [Node]
    func breadcrumb(of id: String?) throws -> [(id: String, name: String)]   // gốc → chính nó; nil ⇒ []
    func createFolder(parentId: String?, name: String) throws -> Node
    func createFile(parentId: String?, name: String, size: Int64, storedSize: Int64, mime: String, codec: Int, crc32: UInt32, blobId: String, mtime: Int64?) throws -> Node
    func fileBlobInfo(_ id: String) throws -> (blobId: String, codec: Int, size: Int64, storedSize: Int64, crc32: UInt32, mime: String, name: String)?   // chỉ file chưa trashed
    func rename(_ id: String, to newName: String) throws -> Node
    func move(_ ids: [String], to parentId: String?) throws -> [Node]
    func trash(_ ids: [String]) throws -> Int
    func restore(_ ids: [String]) throws -> Int
    func purge(_ ids: [String]) throws -> (count: Int, blobIds: [String], thumbNodeIds: [String])
    func emptyTrash() throws -> (count: Int, blobIds: [String], thumbNodeIds: [String])
    func listTrash() throws -> [Node]
    func setHasThumb(_ id: String, _ has: Bool) throws
    func nodeExistsAliveFolder(_ id: String?) throws -> Bool       // nil (gốc) ⇒ true
}
```
Mỗi hàm công khai bọc `db.sync { try db.transaction { … } }` (hàm đọc chỉ `db.sync`).

## Logic chi tiết
- **listChildren**: `WHERE parent_id IS ? AND trashed_at IS NULL`; `ORDER BY kind ASC` (folder=0 trước), rồi theo khóa: `name` ⇒ `name_lower`; `size` ⇒ `size`; `date` ⇒ `modified_at`; `type` ⇒ đuôi (tính trong Swift sau khi lấy, ổn định). `desc` đảo thứ tự **chỉ trong cùng nhóm kind**. Khóa phụ luôn `name_lower ASC, id ASC`. Whitelist cột để tránh chèn chuỗi (map enum → chuỗi cố định).
- **tagIds**: sau khi có `[Node]`, nạp `node_tags` theo lô ≤ 500 id (`WHERE node_id IN (?,?,…)`) và gắn vào.
- **createFolder/createFile**: `NameRules.validate` (nil ⇒ `invalid_name`); parent phải là thư mục sống (`not_found` nếu không); tên `uniqueName` theo `name_lower` của anh em sống; `created_at = modified_at = mtime ?? now` (file), `now` (folder). `kind`, `codec` map int⇄string.
- **rename**: validate; nếu `name_lower` trùng anh em sống khác chính nó ⇒ `name_conflict`; chỉ đổi hoa/thường của chính nó thì cho phép. Cập nhật `name, name_lower, modified_at`.
- **move**: với mỗi id: bỏ qua nếu không tồn tại/đã trashed; nếu đích non-nil và không phải thư mục sống ⇒ `invalid_move`; nếu id là thư mục và đích là chính nó hoặc hậu duệ (đi ngược từ đích lên gốc, gặp id ⇒ vi phạm) ⇒ `invalid_move`; nếu đã ở đúng cha ⇒ bỏ qua; đặt tên unique tại đích. Tất cả trong 1 transaction: lỗi ở id nào thì rollback hết.
- **trash/restore/purge**: đúng `docs/02` mục 3. CTE hậu duệ:
  `WITH RECURSIVE d(id) AS (SELECT ? UNION ALL SELECT n.id FROM nodes n JOIN d ON n.parent_id = d.id) SELECT id FROM d`.
- **purge**: chỉ nhận id mà `trash_root = id`; thu blob_id (kind=1) và id file (để xóa thumb) **trước** khi `DELETE`.
- Thời gian: `Int64(Date().timeIntervalSince1970 * 1000)`; tách thành `static var nowMs: () -> Int64` có thể gán lại trong test.

## Test: `VaultStoreNodesTests.swift`
Tạo cây 3 cấp; sắp xếp 4 khóa × 2 chiều (thư mục luôn trước); tên trùng tự đổi `(1)`; rename trùng ⇒ `name_conflict`, đổi hoa/thường OK; move vào chính nó/hậu duệ ⇒ `invalid_move`; trash thư mục ⇒ hậu duệ ẩn; restore khi cha đã bị trash ⇒ về gốc và tên unique; trash lồng (xóa file con trước rồi xóa thư mục cha) ⇒ restore thư mục không hồi sinh file con đã xóa riêng; purge trả đủ blob ids; emptyTrash; breadcrumb; 3000 node listChildren < 200ms trên CI (chỉ ghi log thời gian, không assert chặt).

## Nghiệm thu
- [ ] Test xanh. [ ] Không còn node mồ côi sau purge (kiểm `SELECT count(*)`). [ ] Đủ invariants `docs/02` mục 5.
