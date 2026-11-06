# 04 — Lưu trữ, nén, upload, tải về, ZIP

## 1. BlobStore (`Storage/BlobStore.swift`)

```swift
final class BlobStore {
    init(root: URL) throws                                // tạo blobs/, thumbs/, tmp/
    func path(forBlob id: String) -> String               // blobs/<id.prefix(2)>/<id>
    func thumbPath(forNode id: String) -> String
    func tmpPath(forUpload id: String) -> String
    func ensureShardDir(forBlob id: String) throws
    func delete(blobId: String)                           // bỏ qua nếu không tồn tại
    func deleteThumb(nodeId: String)
    func fileSize(atPath p: String) -> Int64?             // stat
    func diskFree() -> Int64                              // FileManager.attributesOfFileSystem → .systemFreeSize
    func diskTotal() -> Int64
}
```
Mọi đọc/ghi dùng **fd POSIX**. Helper trong `Net.swift` hoặc `BlobStore`:
```swift
func readFully(fd: Int32, into buf: UnsafeMutableRawPointer, count: Int) throws -> Int   // trả số byte đọc (0 = EOF), xử lý EINTR
func writeFully(fd: Int32, _ buf: UnsafeRawPointer, count: Int) throws                   // lặp tới hết, xử lý EINTR
```

## 2. Chính sách nén (`MimeTypes` + `Compressor`)

Chỉ nén **zlib**, mức cố định của Apple (`COMPRESSION_ZLIB`, đầu ra là raw DEFLATE, **không** có header zlib/gzip).

```swift
enum CompressionPolicy {
    // Quyết định có thử nén không, dựa vào tên file.
    static func decide(name: String, size: Int64) -> Decision   // .never | .always | .sample
}
```
- `.never` nếu `size < 1024` hoặc đuôi thuộc nhóm đã nén: `jpg jpeg png gif webp heic heif avif mp4 m4v mov mkv avi webm wmv flv mp3 aac m4a flac ogg opus wma zip rar 7z gz bz2 xz zst tgz lz4 apk ipa jar docx xlsx pptx odt ods odp epub`.
- `.always` nếu đuôi thuộc nhóm nén tốt: `txt md log csv tsv json xml html htm css js ts svg yaml yml ini conf sql srt vtt bmp tif tiff wav raw dng psd iso vmdk tar c h cpp java py swift`.
- Còn lại (kể cả `pdf`, đuôi lạ): `.sample`.
- `.sample`: nén thử **256KB đầu** (hoặc cả file nếu nhỏ hơn); nếu `compressed/original > 0.85` ⇒ không nén cả file.
- Sau khi nén cả file (`.always` hoặc `.sample` đạt): nếu `storedSize > 0.95 * size` ⇒ **bỏ bản nén, giữ raw** (xóa file nén, dùng `.part` làm blob).
- Upload có `compress=off` ⇒ luôn raw.

## 3. Compressor (`Storage/Compressor.swift`)

Dùng `import Compression`, API `compression_stream`:

```swift
enum Compressor {
    /// Nén dữ liệu đọc từ inFD (tối đa limitInput byte nếu có), mỗi khối đầu ra đưa vào sink.
    /// Trả (số byte vào, số byte ra).
    static func compress(from inFD: Int32, limitInput: Int64?, sink: (UnsafeRawBufferPointer) throws -> Void) throws -> (read: Int64, written: Int64)

    /// Tiện ích: nén cả fd vào fd khác (gọi compress với sink = writeFully(outFD)).
    static func compressFile(from inFD: Int32, to outFD: Int32) throws -> (read: Int64, written: Int64)

    /// Giải nén fd (raw DEFLATE), mỗi lần đưa tối đa 64KB vào sink.
    static func decompress(from inFD: Int32, sink: (UnsafeRawBufferPointer) throws -> Void) throws

    /// Nén thử sampleBytes đầu (sink chỉ đếm byte, không ghi). Trả written/read; fd về vị trí đầu bằng lseek(fd,0,SEEK_SET).
    static func sampleRatio(fd: Int32, sampleBytes: Int) throws -> Double
}
```

Logic `compress`:
1. Cấp `inBuf` 64KB, `outBuf` 64KB (`UnsafeMutablePointer<UInt8>.allocate`, `defer` giải phóng).
2. `var stream = compression_stream(dst_ptr: dummy, dst_size: 0, src_ptr: dummy, src_size: 0, state: nil)` (dummy = một con trỏ hợp lệ bất kỳ); `compression_stream_init(&stream, COMPRESSION_STREAM_ENCODE, COMPRESSION_ZLIB)`; `defer { compression_stream_destroy(&stream) }`.
3. Vòng lặp: khi `stream.src_size == 0` và chưa EOF ⇒ đọc khối tiếp vào `inBuf`, gán `src_ptr=inBuf`, `src_size=n`; nếu `n==0` ⇒ `eof=true`. `flags = eof ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0`. Gán `dst_ptr=outBuf`, `dst_size=64KB`. Gọi `compression_stream_process(&stream, flags)`. Sau đó đưa `64KB - dst_size` byte ra `sink`. Nếu status `COMPRESSION_STATUS_END` ⇒ thoát; `COMPRESSION_STATUS_ERROR` ⇒ ném `CompressError.failed`; `OK` ⇒ lặp.
4. `decompress` tương tự với `COMPRESSION_STREAM_DECODE`; không cần FINALIZE (truyền flag 0, khi hết input truyền FINALIZE); mỗi lần `dst_size` bị lấp đầy một phần thì gọi `sink` với phần đã sinh.
5. Lưu ý Swift: `compression_stream` không có init mặc định tiện; khởi tạo bằng buffer giả:
   ```swift
   let dummy = UnsafeMutablePointer<UInt8>.allocate(capacity: 1); defer { dummy.deallocate() }
   var stream = compression_stream(dst_ptr: dummy, dst_size: 0, src_ptr: UnsafePointer(dummy), src_size: 0, state: nil)
   ```

## 4. UploadManager (`Storage/UploadManager.swift`)

```swift
final class UploadManager {
    init(store: VaultStore, blobs: BlobStore, config: VaultConfig)

    func create(parentId: String?, name: String, size: Int64, mime: String, lastModified: Int64?, compress: Bool) throws -> UploadInfo
    func info(id: String) throws -> UploadInfo
    func appendChunk(id: String, offset: Int64, length: Int, reader: (UnsafeMutableRawPointer, Int) throws -> Int) throws -> Int64
    func finish(id: String) throws                  // chuyển processing, đẩy vào worker serial
    func cancel(id: String) throws
    func cleanupAtStartup()                         // xem docs/02 mục 4
    func receivingBytesTotal() -> Int64             // tổng (size - received) của các upload receiving, để tính quota
}
struct UploadInfo { id, parentId, name, size, received, mime, state, nodeId, error }
```

**create**: validate tên (`NameRules.validate`); parent null hoặc tồn tại & chưa trashed; kiểm quota `size + receivingBytesTotal() + reserveFreeBytes <= diskFree()` else `insufficient_storage`; tạo `tmp/<id>.part` rỗng (`open O_CREAT|O_WRONLY|O_EXCL`, mode 0644); insert dòng `uploads`.

**appendChunk**: lock theo upload id (`NSLock` trong dict, mỗi upload một lock). Đọc dòng; `state` phải là `receiving`; `offset == received` else `offset_mismatch(received)`; `received + length <= size` else `bad_request`. Mở `.part` `O_WRONLY`, `lseek(offset)`. Lặp: `reader(buf, min(64KB, remaining))` → cập nhật `crc = Crc32.update(crc, buf, n)` → `writeFully`. Sau cùng `fsync` **không** gọi (tốn); cập nhật DB `received`, `crc`, `updated_at` **một lần** cuối khối. Nếu socket đứt giữa chừng (reader ném lỗi): vẫn cập nhật `received`/`crc` theo số byte đã ghi, `ftruncate` về `received` cho khớp, rồi ném lại lỗi. Trả `received` mới.

**finish** (đồng bộ phần kiểm tra, xử lý bất đồng bộ):
1. Kiểm `received == size` else `not_ready`. Đặt `state='processing'`.
2. `processQueue.async { process(id) }`.

**process(id)** (chạy trên queue serial `exv.process`):
1. `blobId = IDGen.newID()`; `ensureShardDir`.
2. `decide(name,size)`: nếu `.never` hoặc `compress=0` ⇒ `rename(tmp, blobPath)`; `codec=raw`, `storedSize=size`.
3. Nếu `.sample`: `sampleRatio`; > 0.85 ⇒ như `.never`.
4. Ngược lại: mở `.part` đọc, `blobPath + ".tmpz"` ghi; `Compressor.compressFile`; nếu `written > 0.95*size` ⇒ xóa `.tmpz`, rename `.part` ⇒ raw; còn không ⇒ rename `.tmpz` ⇒ blobPath, xóa `.part`, `codec=zlib`.
5. `mime`: nếu client gửi rỗng ⇒ `MimeTypes.mime(forName:)`.
6. `store.createFile(parentId,name,size,storedSize,mime,codec,crc,blobId,mtime)` (tên tự unique; nếu `parentId` đã bị xóa/trashed trong lúc upload thì rơi về gốc). Thành công ⇒ `state='done', node_id=…`.
7. Lỗi bất kỳ ⇒ xóa blob/tmp đã tạo, `state='error', error=<message>`.
8. Luôn bắt mọi lỗi; không để thread worker chết.

## 5. Tải về (`Api/FilesApi.swift`)

- Truy vấn node (`kind=1`, chưa trashed) rồi **thả DB** trước khi stream.
- `codec=raw`: mở blob; parse `Range` bằng `RangeParser`; `pread` từng 64KB; header `Content-Length`, `Content-Range`, `206` khi có Range hợp lệ.
- `codec=zlib`: `Compressor.decompress(from: fd) { chunk in try writer.write(chunk) }`; `Content-Length = size`; không Range.
- Nếu socket ghi lỗi (EPIPE/ECONNRESET) ⇒ dừng êm, đóng fd, không log lỗi nặng.

## 6. ZipWriter (`Storage/ZipWriter.swift`)

Chỉ dùng phương thức **stored (0)**, không ZIP64. Tên mục UTF-8 (cờ bit 11 = `0x0800`). Mọi file đã biết `size` và `crc32` từ DB nên **không cần data descriptor**.

```swift
struct ZipEntry { let path: String; let isDir: Bool; let size: Int64; let crc32: UInt32; let node: Node? }
final class ZipWriter {
    init(entries: [ZipEntry])
    static func totalLength(entries: [ZipEntry]) -> Int64
    func write(to writer: ResponseWriter, openData: (ZipEntry, (UnsafeRawBufferPointer) throws -> Void) throws -> Void) throws
}
```
- Local file header (30 byte + tên): `0x04034B50`, version needed `20`, flags `0x0800`, method `0`, mod time/date (DOS, lấy từ `modified_at`; nếu lỗi dùng `0x0000/0x0021`), `crc32`, `compSize=size`, `uncompSize=size`, `nameLen`, `extraLen=0`. Sau đó dữ liệu.
- Central directory header (46 byte + tên): `0x02014B50`, version made by `20`, version needed `20`, flags `0x0800`, method `0`, time, date, crc32, sizes, nameLen, extraLen 0, commentLen 0, disk 0, internal attr 0, external attr (`0x10` nếu thư mục), offset của local header.
- End of central directory (22 byte): `0x06054B50`, disk 0, disk CD 0, số mục, số mục, size CD, offset CD, comment 0.
- Thư mục: tên kết thúc bằng `/`, size 0, crc 0.
- `totalLength = Σ(30 + nameLen + size) + Σ(46 + nameLen) + 22`.
- Mọi số little-endian. Offset/size > `0xFFFFFFFF` hoặc > 65535 mục ⇒ ZipApi trả `too_large` **trước khi** bắt đầu stream.
- Dữ liệu từng file: `codec=raw` ⇒ `pread` blob; `codec=zlib` ⇒ `Compressor.decompress`. `openData` do ZipApi cung cấp.
- Dựng danh sách `entries` bằng `VaultStore.zipEntries(forIds:)` (đệ quy, thứ tự: thư mục rồi nội dung, đường dẫn tương đối từ mục được chọn; tên trùng trong cùng cấp thì tự thêm ` (n)`).

Unit test bắt buộc: tạo zip trong bộ nhớ (writer cài đặt `ResponseWriter` ghi vào `Data`), kiểm độ dài đúng bằng `totalLength`, chữ ký đúng, và ghi ra file rồi `unzip -t` trên CI (trong integration script).

## 7. CRC32 (`Util/Crc32.swift`)

Bảng 256 phần tử, đa thức `0xEDB88320`. Hàm chạy dần, cho phép resume:
```swift
enum Crc32 {
    static func update(_ crc: UInt32, _ buf: UnsafeRawBufferPointer) -> UInt32
    // c = ~crc; for b in buf { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }; return ~c
    static func of(_ data: Data) -> UInt32          // update(0, data)
}
```
Test vector: `Crc32.of("123456789") == 0xCBF43926`; chia đôi chuỗi rồi `update` nối tiếp phải cùng kết quả.
