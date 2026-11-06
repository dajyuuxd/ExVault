# T08 — Router, RangeParser, StaticFiles

**Đọc**: `docs/05` mục 3–5.

## File: `Http/Router.swift`, `Http/RangeParser.swift`, `Http/StaticFiles.swift`
Cài đúng chữ ký. Chi tiết:
- Router: thêm `routeCount` để test; `dispatch` bọc `do/catch`: `ApiError` ⇒ `HttpResponse.error`; `StoreError` ⇒ map `code` ⇒ HTTP theo bảng `docs/03` (hàm `ApiError.from(_ e: StoreError) -> ApiError`); lỗi khác ⇒ `500 internal` và `Log.error`.
- `HttpResponse.error`: body `{"error":{"code","message", ...extra}}`.
- StaticFiles: dùng `realpath()` (Darwin) chống symlink thoát root; `serve` với `HEAD` do HttpServer xử lý (không phải ở đây).

## Test: `RouterTests.swift`, `RangeParserTests.swift`, `StaticFilesTests.swift`
Router: khớp `:id`, 404, 405 có `Allow`, 401 khi `auth=true`, bắt lỗi ném ra. Range: bảng ở `docs/05` mục 4 (đủ 7 ca + `size==0`). Static: `/` ⇒ index; `/../secret`, `/%2e%2e/secret`, `//etc/passwd`, đường dẫn có NUL ⇒ nil/404; ETag + 304; MIME đúng cho `.js` `.css`.

## Nghiệm thu
- [ ] Test xanh. [ ] Không có đường nào thoát khỏi `webRoot`.
