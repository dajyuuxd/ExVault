# T04 — VaultStore: tags, search, stats

**Đọc**: `docs/02`, `docs/03` mục Tag / search / stats.

## Thêm vào `Storage/VaultStore.swift` (hoặc extension trong `VaultStore+Tags.swift`)
```swift
struct Tag: Codable { var id: Int64; var name: String; var color: String }
struct VaultStats: Codable { var fileCount: Int64; var folderCount: Int64; var totalBytes: Int64; var storedBytes: Int64; var trashBytes: Int64 }

func listTags() throws -> [Tag]                                   // ORDER BY name COLLATE NOCASE
func createTag(name: String, color: String?) throws -> Tag        // trùng ⇒ StoreError name_conflict
func updateTag(id: Int64, name: String?, color: String?) throws -> Tag
func deleteTag(id: Int64) throws                                  // cascade node_tags
func applyTags(ids: [String], add: [Int64], remove: [Int64]) throws -> [Node]
func search(q: String?, tagId: Int64?, limit: Int) throws -> [(node: Node, pathText: String)]
func stats() throws -> VaultStats
func zipEntries(forIds ids: [String]) throws -> [ZipEntry]        // viết ở T12, để trống ở task này
```
## Logic
- Tên tag: trim, 1–32 ký tự, không ký tự điều khiển ⇒ sai thì `invalid_name`. Màu mặc định `#888888`; regex `^#[0-9a-fA-F]{6}$` sai ⇒ `StoreError(code:"bad_request")`.
- **applyTags**: bỏ qua node/tag không tồn tại; `INSERT OR IGNORE INTO node_tags`, `DELETE FROM node_tags WHERE node_id=? AND tag_id=?`. Trả lại các Node (chưa trashed) đã cập nhật `tagIds`.
- **search**: bắt buộc `q` (sau trim, không rỗng) hoặc `tagId`. `q` được escape `\`→`\\`, `%`→`\%`, `_`→`\_`, lower-case, rồi `name_lower LIKE ? ESCAPE '\'` với `%q%`. Chỉ node `trashed_at IS NULL`. Giới hạn 500. `pathText`: dựng từ `breadcrumb(of: parentId)` thành `/a/b` (gốc là `/`). Sắp xếp thư mục trước, rồi `name_lower`.
- **stats**: `fileCount/totalBytes/storedBytes` từ node file chưa trashed; `folderCount` thư mục chưa trashed; `trashBytes = SUM(stored_size)` của file trashed.

## Test: `VaultStoreTagsTests.swift`
Tag CRUD + trùng tên không phân biệt hoa thường; màu sai; áp/gỡ tag hàng loạt; xóa tag gỡ khỏi node; search `%` và `_` literal, tiếng Việt có dấu (`Ảnh`), lọc tag, kết quả không chứa node trashed; stats khớp sau trash/restore.

## Nghiệm thu
- [ ] Test xanh. [ ] Search không dùng nối chuỗi từ input.
