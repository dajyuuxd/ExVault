# 05 — HTTP server, Router, Auth

## 1. Kiểu dữ liệu (`Http/HttpTypes.swift`)

```swift
struct HttpRequest {
    let method: String                 // "GET" ...
    let path: String                   // đã percent-decode, không gồm query
    let query: [String: String]        // đã decode; khóa trùng: lấy giá trị cuối
    let headers: [String: String]      // khóa viết thường
    let cookies: [String: String]
    let remoteIP: String
    let body: BodyReader
    var params: [String: String]       // do Router điền (:id)
}
final class BodyReader {
    let contentLength: Int64                    // 0 nếu không có body
    private(set) var remaining: Int64
    func read(into buf: UnsafeMutableRawPointer, max: Int) throws -> Int   // 0 khi hết; không đọc quá remaining
    func readAll(limit: Int) throws -> Data      // > limit ⇒ HttpError.tooLarge
    func discardRemaining() throws               // đọc bỏ phần còn lại (để giữ keep-alive); nếu > 8MB còn lại thì đánh dấu đóng kết nối
}
protocol ResponseWriter { func write(_ ptr: UnsafeRawPointer, count: Int) throws }
extension ResponseWriter { func write(_ data: Data) throws }

enum ResponseBody {
    case none
    case data(Data)
    case stream(length: Int64?, writer: (ResponseWriter) throws -> Void)   // length nil ⇒ dùng chunked
}
struct HttpResponse {
    var status: Int
    var headers: [(String, String)]
    var body: ResponseBody
    static func json(_ obj: Encodable, status: Int = 200) -> HttpResponse
    static func jsonRaw(_ dict: [String: Any], status: Int = 200) -> HttpResponse
    static func error(_ err: ApiError) -> HttpResponse
    static func empty(_ status: Int) -> HttpResponse
}
struct ApiError: Error { let status: Int; let code: String; let message: String; var extra: [String: Any]? ; static func notFound(_ m: String = "not found") -> ApiError ... }
```
Dùng `JSONEncoder` + `JSONSerialization` (đều có từ iOS 7+). Không đặt `outputFormatting` đặc biệt.

## 2. HttpServer (`Http/HttpServer.swift`)

```swift
final class HttpServer {
    init(maxConnections: Int, handler: @escaping (HttpRequest) -> HttpResponse)
    func start(port: UInt16) throws -> UInt16      // thử port...port+10, trả port thực
    func stop()
}
```
**Socket**: `socket(AF_INET, SOCK_STREAM, 0)`, `SO_REUSEADDR`, `bind` tới `INADDR_ANY`, `listen(fd, 16)`. Thread `accept` riêng (`Thread` hoặc `DispatchQueue` riêng). Mỗi socket kết nối: `SO_NOSIGPIPE=1`, `SO_RCVTIMEO=30s`, `SO_SNDTIMEO=30s`, `TCP_NODELAY=1`.

**Vòng lặp kết nối (keep-alive)**:
1. Đọc cho tới `\r\n\r\n` (tối đa 16KB; vượt ⇒ `431`/đóng). Idle chờ request kế tiếp: `SO_RCVTIMEO=15s`, hết giờ ⇒ đóng êm.
2. Parse dòng đầu: `METHOD SP target SP HTTP/1.1`. Chỉ hỗ trợ `GET HEAD POST PUT PATCH DELETE`; khác ⇒ `405`. Header: `Name: value` (trim), key lowercase. `Transfer-Encoding: chunked` từ client ⇒ `411` (không hỗ trợ). `Content-Length` không hợp lệ ⇒ `400`.
3. Tách `target` thành path + query; percent-decode (UTF-8; sai ⇒ `400`). Parse cookie từ header `cookie`.
4. Byte dư sau header trong buffer đầu phải được trao lại cho `BodyReader` (đừng bỏ mất).
5. Gọi `handler(req)`. Ghi response:
   - `data`: `Content-Length` đúng.
   - `stream(length: n)`: `Content-Length: n`; `stream(length:nil)`: `Transfer-Encoding: chunked`.
   - Luôn có `Date`? (không bắt buộc) và `Connection: keep-alive` hoặc `close`, `Server: ExVault`.
   - `HEAD`: gửi header y hệt `GET` nhưng không body.
6. Sau response: `req.body.discardRemaining()`; nếu client gửi `Connection: close`, hoặc lỗi ghi, hoặc handler đặt cờ đóng ⇒ đóng; ngược lại lặp lại.
7. Mọi lỗi I/O ⇒ đóng socket êm (không crash). `signal(SIGPIPE, SIG_IGN)` ở `start`.
8. Hết slot (`DispatchSemaphore.wait(timeout: .now())` thất bại) ⇒ gửi `503` JSON `busy` rồi đóng.

Handler không ném lỗi ra ngoài: `Router.dispatch` bắt `ApiError` và mọi `Error` khác (⇒ `500 internal`, log chi tiết).

## 3. Router (`Http/Router.swift`)

```swift
final class Router {
    typealias Handler = (inout HttpRequest) throws -> HttpResponse
    func add(_ method: String, _ pattern: String, auth: Bool = true, _ handler: @escaping Handler)
    func dispatch(_ req: HttpRequest, authCheck: (HttpRequest) -> Bool) -> HttpResponse
}
```
- Pattern tách theo `/`; segment bắt đầu `:` là tham số. So khớp từng segment, không regex.
- Không khớp path ⇒ `404`; khớp path nhưng sai method ⇒ `405` (kèm `Allow`).
- `auth == true` mà `authCheck` false ⇒ `401 unauthorized`.
- Route tĩnh (`GET /`, `/css/*`, `/js/*`) đăng ký riêng, `auth=false` (trang HTML và JS không chứa bí mật).

## 4. RangeParser (`Http/RangeParser.swift`)

```swift
enum RangeResult { case none, full, partial(start: Int64, end: Int64), invalid }
static func parse(header: String?, size: Int64) -> RangeResult
```
- `nil` hoặc không bắt đầu `bytes=` ⇒ `.none` (phục vụ 200 đầy đủ).
- Có dấu phẩy (nhiều khoảng) ⇒ `.none`.
- `a-b`: `a<=b`, `a<size`; `b` kẹp về `size-1`. `a-`: tới hết. `-n` (n>0): `n` byte cuối (n kẹp `size`). `size==0` + Range ⇒ `.invalid`.
- `a >= size` hoặc cú pháp sai ⇒ `.invalid` ⇒ `416` + `Content-Range: bytes */<size>`.
Test: `bytes=0-0`, `bytes=5-`, `bytes=-5`, `bytes=0-999999` (kẹp), `bytes=9999-` (invalid), `bytes=a-b`, `bytes=0-1,5-6`.

## 5. StaticFiles (`Http/StaticFiles.swift`)

```swift
struct StaticFiles {
    init(root: URL)
    func resolve(urlPath: String) -> String?      // trả đường dẫn tuyệt đối an toàn hoặc nil
    func serve(urlPath: String, ifNoneMatch: String?) -> HttpResponse
}
```
- `/` ⇒ `index.html`. `resolve`: từ chối path chứa `..`, `\0`, bắt đầu không phải `/`; ghép với root; `realpath` kết quả phải có tiền tố là `realpath(root)`; phải là file thường.
- `Content-Type` từ `MimeTypes` (`html css js json svg png ico`), thêm `; charset=utf-8` cho text.
- `ETag: "<mtime>-<size>"`; `If-None-Match` khớp ⇒ `304`. `Cache-Control: no-cache`.
- Phục vụ bằng stream 64KB (file nhỏ nên đọc `Data` cũng được, nhưng dùng stream cho nhất quán).

## 6. Auth (`Auth/*`)

```swift
struct Credentials { let username: String; let password: String
    static func generate() -> Credentials }
```
- `username`: 5 ký tự từ bảng `abcdefghjkmnpqrstuvwxyz` (bỏ i, l, o). `password`: 8 ký tự từ `abcdefghjkmnpqrstuvwxyz23456789` (bỏ i,l,o,0,1). Sinh bằng `SystemRandomNumberGenerator` (`Int.random(in:using:)` hoặc `UInt8.random`), **không** dùng `rand()`.

```swift
final class SessionStore {
    init(maxSessions: Int, ttl: TimeInterval = 7*24*3600)
    func create() -> String                  // token = 32 byte ngẫu nhiên hex (64 ký tự); vượt max ⇒ loại phiên cũ nhất
    func validate(_ token: String?) -> Bool  // còn hạn ⇒ gia hạn (sliding) và true
    func destroy(_ token: String?)
    func count() -> Int
}
```
Lưu trong RAM (mất khi tắt app: đúng ý đồ vì mật khẩu cũng đổi). Dùng `NSLock`.

```swift
final class RateLimiter {
    init(maxFailures: Int = 5, window: TimeInterval = 60, lockout: TimeInterval = 60)
    func allowed(ip: String) -> TimeInterval?     // nil = cho phép; ngược lại số giây phải chờ
    func recordFailure(ip: String)
    func recordSuccess(ip: String)
}
```
- Mỗi IP: danh sách thời điểm thất bại trong `window`; ≥ `maxFailures` ⇒ khóa `lockout` giây ⇒ `429` + `Retry-After`. Dọn entry cũ mỗi lần gọi. Tối đa 256 IP được theo dõi (vượt thì xóa entry cũ nhất).

**Login**: `POST /api/login`: kiểm `RateLimiter.allowed` trước; so sánh `username` và `password` bằng hàm **thời gian hằng** `constantTimeEquals(a, b)` (so cả độ dài, XOR dồn); sai ⇒ `recordFailure` + `401 bad_credentials`; đúng ⇒ `recordSuccess`, `SessionStore.create()`, `Set-Cookie`.

**Cookie**: `exv_sid=<token>; Path=/; HttpOnly; SameSite=Strict; Max-Age=604800`. Không đặt `Secure` (HTTP LAN).

**authCheck**: lấy `cookies["exv_sid"]` ⇒ `SessionStore.validate`.
