# T12 — ZipWriter + endpoint

**Đọc**: `docs/04` mục 6, `docs/03` (`POST /api/zip`).

## File: `Storage/ZipWriter.swift`, `Api/ZipApi.swift`, bổ sung `VaultStore.zipEntries`
- `ZipEntry`, `ZipWriter` đúng `docs/04` mục 6. Viết số little-endian bằng helper `appendLE16/32`.
- `VaultStore.zipEntries(forIds:)`: với mỗi id (sống): file ⇒ 1 entry; thư mục ⇒ entry thư mục + đệ quy con (chỉ sống). Path: `<tên>` hoặc `<tên thư mục>/<tên con>`; trùng ở cùng cấp thì thêm ` (n)`. Thứ tự duyệt ổn định theo `name_lower`.
- `ZipApi`: `POST /api/zip`: đọc body form (≤ 1MB), tách `ids`; lấy entries; kiểm `count <= 65535` và `totalLength <= 0xFFFFFFFF` (không thì `413 too_large`); entries rỗng ⇒ `400 bad_request`. Trả `ResponseBody.stream(length: total)`; `openData` dựa vào `store.fileBlobInfo` + `BlobStore.path` (raw: `pread`; zlib: `Compressor.decompress`).
- Đặt tên file tải: `exvault.zip` (1 mục chọn ⇒ `<tên mục>.zip` đã làm sạch).

## Test: `ZipTests.swift`
Writer vào bộ nhớ: độ dài == `totalLength`; chữ ký local/central/EOCD đúng vị trí; thư mục rỗng; tên UTF-8; CRC khớp. Qua HTTP: chọn thư mục lồng 2 cấp có file raw và zlib ⇒ lưu ra file; trong test dùng `Process` chạy `/usr/bin/unzip -t` (macOS có sẵn) ⇒ exit 0; giải nén so nội dung. Vượt 65535 mục (giả bằng `entries` ảo ở test unit của `ZipApi.validate`) ⇒ `too_large`.

## Nghiệm thu
- [ ] Test xanh trên CI. [ ] `Content-Length` đúng từng byte (client không báo lỗi).
