# T11 — API: upload, content, thumb

**Đọc**: `docs/03` mục Upload/File, `docs/04` mục 4–5, `docs/05` mục 4.

## File: `Api/UploadApi.swift`, `Api/FilesApi.swift`; đăng ký trong `VaultServer`

**UploadApi**
- `POST /api/upload`: parse JSON ⇒ `uploads.create` ⇒ `201 {uploadId, offset:0, chunkSize}`.
- `GET /api/upload/:id`: `{uploadId,state,offset:received,size,node?,error?}`; `node` là `Node` đầy đủ khi `done`.
- `PUT /api/upload/:id?offset=N`: yêu cầu `Content-Length` (>0, ≤ 8MB; thiếu ⇒ `411`/`bad_request`). Gọi `appendChunk(id, offset, length: contentLength) { buf, max in try req.body.read(into: buf, max: max) }`. Trả `{offset}`. **Không** gọi `readAll`.
- `POST /api/upload/:id/finish`: `uploads.finish`; đã `done` ⇒ `200 {"state":"done","node":…}`, ngược lại `202 {"state":"processing"}`.
- `DELETE /api/upload/:id` ⇒ `204`.

**FilesApi**
- `GET /api/files/:id/content`:
  1. `store.fileBlobInfo(id)` (nil ⇒ 404). Thả DB.
  2. `ETag: "<crc hex>-<size>"`; `If-None-Match` khớp ⇒ `304`.
  3. `codec raw`: `RangeParser.parse(header, size)`. `.none` ⇒ `200` + `Content-Length=size`; `.partial` ⇒ `206`, `Content-Range: bytes s-e/size`, `Content-Length=e-s+1`; `.invalid` ⇒ `416` + `Content-Range: bytes */size`. Stream bằng `pread` 64KB (mở fd trong closure writer; `defer close`).
  4. `codec zlib`: `200`, `Content-Length=size`, `Accept-Ranges: none`, stream `Compressor.decompress`. Mọi `Range` bị bỏ qua.
  5. `Content-Type`: `mime` rỗng ⇒ `application/octet-stream`; text/* thêm `; charset=utf-8`.
  6. `Content-Disposition`: `inline` hoặc `attachment` (nếu `dl=1`) kèm `filename="<ascii-fallback>"; filename*=UTF-8''<percent-encoded>`. ASCII fallback thay ký tự không-ASCII và `"` `\` bằng `_`.
  7. Header `Accept-Ranges: bytes` (raw) hoặc `none` (zlib); `Cache-Control: private, no-cache`.
- `GET /api/files/:id/thumb`: kiểm node sống và `has_thumb`; đọc file `thumbs/<id>.jpg` (≤256KB, được phép đọc vào `Data`); `Content-Type: image/jpeg`; `Cache-Control: private, max-age=86400`.
- `PUT /api/files/:id/thumb`: `Content-Length` ≤ 256KB (vượt ⇒ `413 too_large`); ghi file tạm rồi `rename` thành `thumbs/<id>.jpg`; kiểm 2 byte đầu `FF D8` nếu không ⇒ `bad_request`; `store.setHasThumb(id,true)`; `204`.

## Test: `ApiFilesTests.swift`
Upload hết luồng bằng HTTP (3 khối, poll tới `done`); `.txt` ⇒ `codec:"zlib"` và `content` trả đúng byte; `.bin` raw + `Range: bytes=10-19` ⇒ 206 đúng 10 byte đúng nội dung; `bytes=-5`; `bytes=999999999-` ⇒ 416; `If-None-Match` ⇒ 304; `dl=1` có `attachment` + `filename*` đúng cho tên tiếng Việt; thumb PUT/GET; thumb sai magic ⇒ 400; PUT chunk sai offset ⇒ 409 có `offset`; ngắt kết nối giữa khối rồi resume; tải file đang trashed ⇒ 404; HEAD content trả header đúng không body.

## Nghiệm thu
- [ ] Test xanh. [ ] Không `readAll` cho khối upload.
