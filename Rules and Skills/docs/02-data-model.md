# 02 — Mô hình dữ liệu

## 1. SQLite (file `vault.db`)

Mở bằng `SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX`. PRAGMA khi mở:
```
PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; PRAGMA foreign_keys=ON;
PRAGMA cache_size=-2000; PRAGMA mmap_size=0; PRAGMA temp_store=FILE;
```
`PRAGMA user_version` = phiên bản schema (hiện là **1**). Migration: nếu `user_version==0` chạy toàn bộ schema dưới đây rồi đặt `1`.

```sql
CREATE TABLE nodes (
  id           TEXT PRIMARY KEY,
  parent_id    TEXT REFERENCES nodes(id) ON DELETE CASCADE,  -- NULL = gốc
  kind         INTEGER NOT NULL,            -- 0 = folder, 1 = file
  name         TEXT NOT NULL,
  name_lower   TEXT NOT NULL,               -- name.lowercased()
  size         INTEGER NOT NULL DEFAULT 0,  -- byte gốc (file); 0 với folder
  stored_size  INTEGER NOT NULL DEFAULT 0,  -- byte thực trên đĩa
  mime         TEXT NOT NULL DEFAULT '',
  codec        INTEGER NOT NULL DEFAULT 0,  -- 0 = raw, 1 = zlib (raw DEFLATE của Apple Compression)
  crc32        INTEGER NOT NULL DEFAULT 0,  -- CRC32 của dữ liệu gốc (UInt32 lưu dạng Int64)
  blob_id      TEXT,                        -- NULL với folder
  has_thumb    INTEGER NOT NULL DEFAULT 0,
  created_at   INTEGER NOT NULL,
  modified_at  INTEGER NOT NULL,
  trashed_at   INTEGER,                     -- NULL = chưa xóa
  trash_root   TEXT                         -- id node gốc của lần xóa (để restore/empty)
);
CREATE INDEX idx_nodes_parent ON nodes(parent_id, trashed_at, kind, name_lower);
CREATE INDEX idx_nodes_name   ON nodes(name_lower);
CREATE INDEX idx_nodes_trash  ON nodes(trashed_at) WHERE trashed_at IS NOT NULL;

CREATE TABLE tags (
  id    INTEGER PRIMARY KEY AUTOINCREMENT,
  name  TEXT NOT NULL UNIQUE COLLATE NOCASE,
  color TEXT NOT NULL DEFAULT '#888888'      -- dạng #rrggbb
);
CREATE TABLE node_tags (
  node_id TEXT    NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
  tag_id  INTEGER NOT NULL REFERENCES tags(id)  ON DELETE CASCADE,
  PRIMARY KEY (node_id, tag_id)
);
CREATE INDEX idx_node_tags_tag ON node_tags(tag_id);

CREATE TABLE uploads (
  id          TEXT PRIMARY KEY,
  parent_id   TEXT,                 -- NULL = gốc
  name        TEXT NOT NULL,
  size        INTEGER NOT NULL,     -- tổng byte client khai báo
  received    INTEGER NOT NULL DEFAULT 0,
  crc         INTEGER NOT NULL DEFAULT 0,   -- CRC32 chạy dần của phần đã nhận
  mime        TEXT NOT NULL DEFAULT '',
  mtime       INTEGER,              -- lastModified của file gốc (ms), có thể NULL
  compress    INTEGER NOT NULL DEFAULT 1,   -- 1 = auto, 0 = off
  state       TEXT NOT NULL DEFAULT 'receiving',  -- receiving | processing | done | error
  node_id     TEXT,                 -- có khi state=done
  error       TEXT,
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL
);
```

Gốc (`parent_id IS NULL`) không có dòng riêng. Khi truy vấn so sánh cha dùng `parent_id IS ?` (SQLite so khớp NULL đúng với `IS`).

## 2. Quy tắc tên (`NameRules`)

- `validate(raw)`: trim khoảng trắng đầu/cuối; từ chối chuỗi rỗng, `.`, `..`, chứa `/`, `\`, ký tự điều khiển (U+0000–U+001F, U+007F), dài > 255 byte UTF-8. Trả `nil` nếu sai → lỗi `invalid_name`.
- Trùng tên cùng thư mục (không phân biệt hoa thường, so `name_lower`, chỉ xét node `trashed_at IS NULL`):
  - **Tạo mới / upload / di chuyển / restore**: tự đổi `a.txt` → `a (1).txt`, `a (2).txt`... (`NameRules.uniqueName`). Với thư mục: `docs` → `docs (1)`. Phần mở rộng là sau dấu chấm cuối cùng, nếu tên bắt đầu bằng dấu chấm và không còn dấu chấm khác thì coi như không có đuôi.
  - **Đổi tên thủ công**: trùng thì lỗi `name_conflict` (409).

## 3. Thùng rác

- `trash(ids)`: với mỗi id (chưa trashed): đặt `trashed_at=now`, `trash_root=<id>` cho node đó **và mọi hậu duệ** (CTE đệ quy), chỉ cập nhật hậu duệ chưa trashed. Hậu duệ đã trashed từ trước giữ nguyên `trash_root` cũ.
- Danh sách thùng rác (`listTrash`) chỉ trả node có `trash_root = id` (tức gốc của lần xóa).
- `restore(ids)` (id là gốc trash): nếu `parent_id` còn tồn tại và `trashed_at IS NULL` thì giữ, ngược lại chuyển về gốc. Đặt tên unique tại nơi đích cho node gốc. Sau đó đặt `trashed_at=NULL, trash_root=NULL` cho mọi node có `trash_root = id`.
- `purge(ids)` (id là gốc trash): xóa node gốc (hậu duệ bị xóa theo `ON DELETE CASCADE`); trước đó thu `blob_id` của mọi file trong cây; trả danh sách blob id để gọi `BlobStore.delete` **sau khi commit**.
- `emptyTrash()`: purge mọi gốc trash.
- Node trashed không xuất hiện trong list/search/zip/stats (trừ `trashBytes`).
- Không tự xóa thùng rác theo thời gian.

## 4. Thư mục dữ liệu

```
<dataDir>/
  vault.db  vault.db-wal  vault.db-shm
  blobs/<2 ký tự đầu blobId>/<blobId>      # dữ liệu file (raw hoặc zlib)
  thumbs/<nodeId>.jpg                      # thumbnail JPEG do trình duyệt tạo
  tmp/<uploadId>.part                      # dữ liệu upload đang nhận
```
Khi khởi động (`VaultServer.init`): tạo thư mục nếu thiếu; xóa `tmp/*.part` không có dòng trong `uploads` hoặc `updated_at` quá 24 giờ (và dòng DB tương ứng); mọi upload `state='processing'` còn sót (do app bị kill) đặt về `error` với message `interrupted`.

## 5. Invariants (agent phải giữ)

1. `kind=0` ⇒ `blob_id IS NULL`, `size=0`.
2. `kind=1` ⇒ file `blobs/xx/<blob_id>` tồn tại và dài đúng `stored_size`.
3. `codec=0` ⇒ `stored_size==size`; `codec=1` ⇒ giải nén ra đúng `size` byte và CRC32 khớp `crc32`.
4. Không có hai node cùng cha, cùng `name_lower`, cùng `trashed_at IS NULL`.
5. Không thể di chuyển thư mục vào chính nó hay hậu duệ của nó (`invalid_move`).
6. Nếu ghi DB thất bại sau khi đã tạo blob ⇒ xóa blob vừa tạo.
