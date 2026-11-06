# T06 — UploadManager

**Đọc**: `docs/04` mục 4, `docs/02` mục 4–5, `docs/03` mục Upload.

## File: `Storage/UploadManager.swift`
Cài đúng chữ ký & logic `docs/04` mục 4. Chi tiết:
- Lỗi dùng `StoreError` với code đúng bảng `docs/03` (`offset_mismatch` kèm `extra offset`: thêm trường `var extra: [String: Int64] = [:]` vào `StoreError`).
- Khóa theo upload: `private var locks: [String: NSLock]` bảo vệ bằng một `NSLock` chung; xóa khóa khi `cancel` hoặc xong.
- `processQueue = DispatchQueue(label: "exv.process", qos: .utility)` serial.
- `process` phải tự bắt mọi lỗi và cập nhật `state`. Hook test: `var onProcessed: ((String) -> Void)?` gọi sau khi state là `done|error`.
- `cleanupAtStartup()`: theo `docs/02` mục 4; được gọi từ `VaultServer.init`.
- Khi `finish` được gọi lần hai lúc `state=processing|done`: không ném lỗi.
- `info(id:)` ném `not_found` nếu không có.

## Test: `UploadManagerTests.swift`
1. Upload `.txt` 300KB chia 3 khối ⇒ `done`, `codec=zlib`, `storedSize < size`, tải lại giải nén khớp CRC.
2. Upload `.jpg` 1MB ngẫu nhiên ⇒ `codec=raw`, `storedSize==size`.
3. Upload `.bin` ngẫu nhiên ⇒ sample ⇒ raw. `.bin` toàn số 0 ⇒ zlib.
4. File 0 byte ⇒ `done`, raw.
5. Sai offset ⇒ `offset_mismatch` kèm offset đúng; resume từ offset đó thành công.
6. Reader ném lỗi giữa khối ⇒ `received` phản ánh đúng số byte đã ghi, `.part` được cắt khớp; gửi lại từ `received` thành công.
7. Hủy ⇒ xóa `.part` + dòng DB. `finish` khi chưa đủ byte ⇒ `not_ready`.
8. Tên trùng ⇒ node có `(1)`. Parent bị trash giữa chừng ⇒ rơi về gốc.
9. `compress=off` với `.txt` ⇒ raw.
10. Quota: giả `diskFree` nhỏ (thêm `var diskFreeProvider: () -> Int64` vào BlobStore để test) ⇒ `insufficient_storage`.
11. `cleanupAtStartup` xóa `.part` mồ côi và đổi `processing` ⇒ `error`.

## Nghiệm thu
- [ ] Test xanh. [ ] Không có chỗ nào đọc cả file vào `Data`.
