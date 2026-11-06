# T05 — BlobStore + Compressor

**Đọc**: `docs/04` mục 1–3.

## File: `Storage/BlobStore.swift`, `Storage/Compressor.swift`
Cài đúng chữ ký ở `docs/04`. Chi tiết bổ sung:
- `BlobStore.init(root:)`: `createDirectory(withIntermediateDirectories:)` cho `blobs/`, `thumbs/`, `tmp/`.
- `diskFree()`: `try FileManager.default.attributesOfFileSystem(forPath: root)[.systemFreeSize] as? NSNumber` ⇒ `Int64`; lỗi ⇒ 0.
- `Compressor.compress/decompress/sampleRatio/compressFile`: đúng thuật toán `docs/04` mục 3. `enum CompressError: Error { case failed, io(Int32) }`.
- `decompress` dữ liệu hỏng ⇒ ném `CompressError.failed` (không crash, không vòng lặp vô hạn: nếu `process` trả OK nhưng cả `src_size` và lượng `dst` sinh ra đều không đổi 2 lần liên tiếp thì ném lỗi).
- `sampleRatio`: đọc tối đa `sampleBytes` đầu, nén với sink đếm byte; file rỗng ⇒ trả 1.0.

## Test: `CompressorTests.swift`
Round-trip các kích thước: 0, 1, 1023, 65535, 65536, 65537, 1MB, 5MB; dữ liệu: văn bản lặp, byte ngẫu nhiên (`SystemRandomNumberGenerator`), toàn số 0. Kiểm: giải nén == gốc (so CRC32 + độ dài); văn bản nén < 20% gốc; ngẫu nhiên `sampleRatio > 0.95`; dữ liệu hỏng (đổi byte giữa dòng nén) ⇒ ném lỗi hoặc ra dữ liệu khác nhưng **không treo** (đặt timeout test 10 giây). BlobStore: đường dẫn shard, `delete` file không tồn tại không lỗi.

## Nghiệm thu
- [ ] Test xanh. [ ] Không cấp phát buffer > 64KB trong hàm nén/giải nén. [ ] Mọi `allocate` đều có `deallocate` (`defer`).
