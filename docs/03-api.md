# 03 — API

Quy ước: mọi endpoint `/api/*` (trừ `login`, `health`) cần cookie `exv_sid` hợp lệ, nếu không trả `401 unauthorized`. Body JSON `Content-Type: application/json`. Phản hồi JSON UTF-8. `id` là hex 24 ký tự; thư mục gốc dùng chuỗi `root` trong URL/query và `null` trong JSON.

## Lỗi

`{"error":{"code":"<code>","message":"<tiếng Anh ngắn>"}}`

| code | HTTP | Khi nào |
|---|---|---|
| `bad_request` | 400 | JSON sai, thiếu trường, tham số sai |
| `invalid_name` | 400 | tên không hợp lệ |
| `invalid_move` | 400 | di chuyển vào chính nó/hậu duệ, hoặc đích không phải thư mục |
| `unauthorized` | 401 | thiếu/sai cookie |
| `bad_credentials` | 401 | login sai |
| `not_found` | 404 | không có node/upload/tag/route |
| `method_not_allowed` | 405 | sai method |
| `name_conflict` | 409 | đổi tên/tag trùng |
| `offset_mismatch` | 409 | upload sai offset (kèm `"offset":<hiện tại>` ở cấp ngoài cùng của error object) |
| `not_ready` | 409 | upload chưa nhận đủ byte khi finish |
| `too_large` | 413 | body JSON > 1MB, thumbnail > 256KB, zip > 4GB hoặc > 65535 mục |
| `range_not_satisfiable` | 416 | Range sai |
| `rate_limited` | 429 | login sai quá nhiều (kèm header `Retry-After`) |
| `internal` | 500 | lỗi không lường trước |
| `busy` | 503 | hết slot kết nối |
| `insufficient_storage` | 507 | dưới `reserveFreeBytes` |

## Đối tượng

**Node**
```json
{"id":"…","parentId":null,"kind":"file","name":"a.txt","size":1234,"storedSize":600,"mime":"text/plain",
 "codec":"zlib","hasThumb":false,"tagIds":[1,3],"createdAt":1730000000000,"modifiedAt":1730000000000,"trashedAt":null}
```
`kind`: `"folder"|"file"`. `codec`: `"raw"|"zlib"` (folder: `"raw"`). Folder có `size:0`.

**Tag** `{"id":1,"name":"work","color":"#d33"}`

## Auth / hệ thống

| Method & path | Body | Trả |
|---|---|---|
| `GET /api/health` (không cần auth) | – | `200 {"ok":true,"version":"1.0"}` |
| `POST /api/login` | `{"username","password"}` | `204` + `Set-Cookie: exv_sid=<token>; Path=/; HttpOnly; SameSite=Strict; Max-Age=604800`. Sai: `401 bad_credentials`. Quá hạn mức: `429` |
| `POST /api/logout` | – | `204` + cookie hết hạn (`Max-Age=0`) |
| `GET /api/me` | – | `200 {"username":"…","chunkSize":4194304,"limits":{"maxZipBytes":4294967295}}` |
| `GET /api/stats` | – | `200 {"fileCount","folderCount","totalBytes","storedBytes","trashBytes","ratio","diskFree","diskTotal"}` (`ratio = storedBytes/totalBytes`, 1 nếu totalBytes=0; chỉ tính node chưa trashed; `trashBytes` = tổng `stored_size` node trashed) |

## Node

| Method & path | Body/Query | Trả |
|---|---|---|
| `GET /api/nodes?parent=<id\|root>&sort=name\|size\|date\|type&order=asc\|desc` | mặc định `sort=name&order=asc` | `{"parent":{"id":null\|"…","name":"…"},"path":[{"id","name"}…],"items":[Node…]}`. Thư mục luôn đứng trước file. `sort=name` so `name_lower`; `type` theo đuôi file; `date` theo `modified_at`. `path` rỗng nếu ở gốc, gồm các tổ tiên + chính nó. Parent không tồn tại/trashed: `404` |
| `GET /api/nodes/:id` | – | `Node` |
| `POST /api/folders` | `{"parentId":null\|"id","name":"…"}` | `201 Node` (tên tự unique) |
| `PATCH /api/nodes/:id` | `{"name":"…"}` | `200 Node` |
| `POST /api/nodes/move` | `{"ids":[…],"parentId":null\|"id"}` | `200 {"items":[Node…]}` |
| `POST /api/nodes/trash` | `{"ids":[…]}` | `200 {"count":n}` |
| `POST /api/nodes/restore` | `{"ids":[…]}` | `200 {"count":n}` |
| `POST /api/nodes/purge` | `{"ids":[…]}` (chỉ gốc trash) | `200 {"count":n}` (xóa blob + thumb) |
| `GET /api/trash` | – | `{"items":[Node…]}` (chỉ gốc trash, mới xóa trước) |
| `POST /api/trash/empty` | – | `200 {"count":n}` |
| `GET /api/search?q=<text>&tag=<tagId>` | `q` tìm `name_lower LIKE %q%` (escape `%` `_` bằng `ESCAPE '\'`); `tag` lọc theo nhãn; ít nhất một trong hai; tối đa 500 kết quả | `{"items":[Node…]}` mỗi Node có thêm `"pathText":"/a/b"` |
| `POST /api/nodes/tag` | `{"ids":[…],"add":[tagId…],"remove":[tagId…]}` | `200 {"items":[Node…]}` |

Mọi `ids` tối đa 5000 phần tử; id không tồn tại bị bỏ qua (không lỗi), `count` phản ánh số thực xử lý.

## Tag

| Method & path | Body | Trả |
|---|---|---|
| `GET /api/tags` | – | `{"items":[Tag…]}` sắp theo `name` |
| `POST /api/tags` | `{"name","color"?}` | `201 Tag` (trùng tên: `409 name_conflict`) |
| `PATCH /api/tags/:id` | `{"name"?,"color"?}` | `200 Tag` |
| `DELETE /api/tags/:id` | – | `204` |

Tên tag: trim, 1–32 ký tự, không điều khiển. `color` khớp `^#[0-9a-fA-F]{6}$`, sai thì `bad_request`.

## Upload (xem logic ở `docs/04`)

| Method & path | Body | Trả |
|---|---|---|
| `POST /api/upload` | `{"parentId":null\|"id","name","size":int,"mime"?:"","lastModified"?:ms,"compress"?:"auto"\|"off"}` | `201 {"uploadId","offset":0,"chunkSize":4194304}`. Kiểm `size>=0`, tên hợp lệ, parent tồn tại, đủ dung lượng (`size + reserveFreeBytes <= diskFree`, tính cả dữ liệu đang nhận) |
| `GET /api/upload/:id` | – | `{"uploadId","state","offset","size","node"?,"error"?}` |
| `PUT /api/upload/:id?offset=N` | body nhị phân, `Content-Length` bắt buộc, ≤ 8MB | `200 {"offset":<mới>}`. `offset` ≠ `received` hiện tại ⇒ `409 offset_mismatch` (kèm `offset`). Không được vượt `size` |
| `POST /api/upload/:id/finish` | – | `202 {"state":"processing"}`; nếu `received != size` ⇒ `409 not_ready`. Gọi lại khi đã processing/done ⇒ vẫn `202`/`200 {"state":"done","node":Node}` |
| `DELETE /api/upload/:id` | – | `204` (hủy, xóa `.part`) |

## File

| Method & path | Mô tả |
|---|---|
| `GET /api/files/:id/content` | Dữ liệu gốc (đã giải nén). Query `dl=1` ⇒ `Content-Disposition: attachment`, ngược lại `inline`. Hỗ trợ `Range` khi `codec=raw` (header `Accept-Ranges: bytes`); với `codec=zlib` trả `200` đầy đủ, `Accept-Ranges: none`. `Content-Type` = `mime` (rỗng ⇒ `application/octet-stream`). Có `ETag: "<crc32hex>-<size>"` và hỗ trợ `If-None-Match` ⇒ `304`. Chỉ file chưa trashed |
| `GET /api/files/:id/thumb` | JPEG thumbnail, `Cache-Control: private, max-age=86400`; `404` nếu `has_thumb=0` |
| `PUT /api/files/:id/thumb` | body `image/jpeg` ≤ 256KB ⇒ `204`, đặt `has_thumb=1` |
| `POST /api/zip` | Form `application/x-www-form-urlencoded`: `ids=<id1,id2,…>` (client gửi bằng form ẩn để trình duyệt tải trực tiếp). Trả stream `application/zip`, `Content-Disposition: attachment; filename="exvault.zip"`, có `Content-Length` tính trước. Cấu trúc zip: tên các mục được chọn ở gốc, thư mục đệ quy |

## Tĩnh

| Path | Trả |
|---|---|
| `GET /` | `index.html` |
| `GET /css/*`, `GET /js/*` | file trong `webRoot`, `Cache-Control: no-cache`, có `ETag` + `304` |
| Còn lại không khớp | `404` JSON (nếu path bắt đầu `/api/`) hoặc `404 text/plain` |
