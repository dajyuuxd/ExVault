# T01 — Util

**Đọc**: `docs/02` mục 2, `docs/04` mục 2 và 7, `docs/01` mục 4 (Log).

## File: `Sources/ExVaultCore/Util/`
- `IDGen.swift`: `enum IDGen { static func newID() -> String }` — 12 byte ngẫu nhiên (`UInt8.random(in:)` dùng `SystemRandomNumberGenerator`) ⇒ 24 ký tự hex thường. `static func token() -> String` 32 byte ⇒ 64 hex.
- `Crc32.swift`: đúng `docs/04` mục 7.
- `NameRules.swift`: `validate(_:) -> String?`, `uniqueName(_ base: String, exists: (String) -> Bool) -> String`, `splitExt(_ name: String) -> (stem: String, ext: String)` (ext không gồm dấu chấm; tên `.bashrc` ⇒ stem `.bashrc`, ext rỗng; `a.tar.gz` ⇒ stem `a.tar`, ext `gz`). `uniqueName`: nếu `exists(base)` false ⇒ trả `base`; ngược lại thử `stem (1).ext`, `(2)`... (không có ext ⇒ `stem (1)`); giới hạn 10000 lần rồi ném `fatal-free` fallback bằng cách thêm 8 ký tự ngẫu nhiên.
- `MimeTypes.swift`: `static func mime(forName:) -> String` (bảng ≥ 50 đuôi: txt md html htm css js json xml csv svg png jpg jpeg gif webp bmp ico heic mp4 m4v mov webm mkv avi mp3 m4a aac wav flac ogg pdf zip gz tar 7z rar doc docx xls xlsx ppt pptx epub; mặc định `application/octet-stream`; text/* kèm `; charset=utf-8` khi gửi ra ngoài, **không** lưu charset vào DB). Thêm `enum CompressionPolicy` + `Decision` đúng `docs/04` mục 2 (hai tập đuôi là hằng `Set<String>`).
- `Log.swift`: `public enum Log` với `info/warn/error(_ msg: String)`, định dạng `HH:mm:ss [I] msg` (dùng `DateFormatter` tạo **một lần**), in `print`, đưa vào ring buffer 200 dòng (khóa `NSLock`), gọi `sink` nếu có. `recentLines()`.
- `Json.swift`: `enum Json { static func encode<T: Encodable>(_ v: T) throws -> Data; static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T; static func object(_ dict: [String: Any]) throws -> Data }`.
- `Net.swift`: `readFully`, `writeFully` (`docs/04` mục 1); `constantTimeEquals(_ a: String, _ b: String) -> Bool`; `percentDecode(_ s: String) -> String?`; `parseQuery(_ s: String) -> [String: String]`; `localIPv4Addresses() -> [String]` (qua `getifaddrs`, chỉ `AF_INET`, tên interface bắt đầu `en` hoặc `bridge`, bỏ `127.*` và `169.254.*`); `hex(_ data: Data) -> String`.

## Test: `Tests/ExVaultCoreTests/UtilTests.swift`
IDGen độ dài/charset/không trùng 1000 lần; Crc32 vector `123456789` và nối tiếp; NameRules (rỗng, `..`, có `/`, 256 ký tự, tên có Unicode/emoji hợp lệ, trim); uniqueName (`a.txt`→`a (1).txt`, `.bashrc`, `a.tar.gz`, thư mục `docs`); MimeTypes; constantTimeEquals; percentDecode (`%E1%BB%91`); parseQuery.

## Nghiệm thu
- [ ] `swift test` xanh, ≥ 15 test. [ ] Không dùng API iOS ≥ 13. [ ] Không `try!`.
