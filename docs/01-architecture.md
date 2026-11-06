# 01 — Kiến trúc

## 1. Tổng quan

```
Trình duyệt (PC/phone)  ──HTTP LAN──▶  iPhone: ExVault.app
                                         ├─ UIKit shell: hiện user/pass, IP, log, nút Dim
                                         ├─ KeepAlive: idleTimerDisabled + audio im lặng
                                         └─ ExVaultCore (Swift, không UIKit)
                                              ├─ Http: socket server, router, range, static
                                              ├─ Auth: credentials, sessions, rate limit
                                              ├─ Api: handlers JSON
                                              ├─ Storage: SQLite, BlobStore, Compressor, UploadManager, ZipWriter
                                              └─ Util: IDGen, Crc32, NameRules, MimeTypes, Log
```

Logic nằm hết ở server. Web chỉ là client mỏng gọi API (`docs/03-api.md`).

## 2. Cấu trúc repo (cố định)

```
ExVault/
├─ Package.swift                     # chỉ để build/test core + CLI trên macOS (CI)
├─ project.yml                       # XcodeGen → ExVault.xcodeproj (CI tạo, KHÔNG commit .xcodeproj)
├─ .github/workflows/build.yml
├─ scripts/integration.sh            # test curl end-to-end trên CI
├─ Sources/
│  ├─ ExVaultCore/
│  │  ├─ VaultServer.swift           # API công khai (mục 4)
│  │  ├─ Util/ IDGen.swift Crc32.swift NameRules.swift MimeTypes.swift Log.swift Json.swift Net.swift
│  │  ├─ Storage/ Database.swift Schema.swift VaultStore.swift BlobStore.swift Compressor.swift UploadManager.swift ZipWriter.swift
│  │  ├─ Auth/ Credentials.swift SessionStore.swift RateLimiter.swift
│  │  ├─ Http/ HttpServer.swift HttpTypes.swift Router.swift RangeParser.swift StaticFiles.swift
│  │  └─ Api/ ApiContext.swift AuthApi.swift NodesApi.swift TagsApi.swift UploadApi.swift FilesApi.swift ZipApi.swift StatsApi.swift
│  └─ exvault-cli/main.swift         # CLI macOS: chạy server, in user/pass
├─ Tests/ExVaultCoreTests/           # XCTest
├─ App/                              # chỉ iOS
│  ├─ AppDelegate.swift ViewController.swift KeepAlive.swift
│  ├─ LaunchScreen.storyboard
│  └─ Info.plist (do XcodeGen sinh từ project.yml)
└─ Web/                              # tài nguyên tĩnh, đóng gói vào app dạng folder
   ├─ index.html
   ├─ css/app.css
   └─ js/ util.js i18n.js api.js state.js upload.js view.js viewer.js app.js
```

App target biên dịch **trực tiếp** `Sources/ExVaultCore/**` (không dùng SwiftPM trong Xcode) để khỏi phải lo `public`. Chỉ các kiểu ở mục 4 cần `public` (để CLI `import ExVaultCore`). File của App dùng:
```swift
#if canImport(ExVaultCore)
import ExVaultCore
#endif
```

## 3. Luồng chạy

1. `AppDelegate.didFinishLaunching` → tạo `VaultServer(config:)` (sinh `Credentials` ngẫu nhiên) → `start()` trên queue nền → UI hiển thị user/pass/URL.
2. Browser mở `/` → nhận `index.html`; JS gọi `GET /api/me`; 401 thì hiện form đăng nhập.
3. `POST /api/login` → cookie `exv_sid` → SPA tải danh sách (`GET /api/nodes`).
4. Upload: `POST /api/upload` → nhiều `PUT /api/upload/:id?offset=` (mỗi khối 4MB) → `POST /api/upload/:id/finish` → server xử lý nền (nén/đổi tên/ghi DB) → client poll `GET /api/upload/:id` đến `state=done`.
5. Xem: `GET /api/files/:id/content` (Range cho video), `GET /api/files/:id/thumb`.

## 4. API công khai của core (đúng chữ ký này)

```swift
public struct VaultConfig {
    public var dataDir: URL            // <Documents>/ExVault
    public var webRoot: URL            // thư mục Web/
    public var port: UInt16            // mặc định 8080
    public var maxConnections: Int     // 8
    public var maxSessions: Int        // 3
    public var reserveFreeBytes: Int64 // 300 * 1024 * 1024
    public var uploadChunkSize: Int    // 4 * 1024 * 1024
    public init(dataDir: URL, webRoot: URL, port: UInt16 = 8080)
}
public struct Credentials { public let username: String; public let password: String }
public final class VaultServer {
    public init(config: VaultConfig) throws          // mở DB, tạo thư mục, sinh credentials, chưa listen
    public let credentials: Credentials
    public private(set) var boundPort: UInt16        // 0 nếu chưa start
    public func start() throws                       // bind, thử port..port+10; ném lỗi nếu hết
    public func stop()
    public func localAddresses() -> [String]         // ["192.168.1.5"], IPv4, interface en*/bridge*
    public func activeSessionCount() -> Int
    public func diskFreeBytes() -> Int64
}
public enum Log {
    public static var sink: ((String) -> Void)?      // UI gắn vào để nhận dòng log
    public static func recentLines() -> [String]     // ring buffer 200 dòng
}
```

## 5. Luồng thread

- 1 thread `accept` (blocking `accept()`).
- Mỗi kết nối: `DispatchQueue.global(qos: .userInitiated).async`, giới hạn bằng `DispatchSemaphore(value: maxConnections)`. Hết slot → trả `503 busy` rồi đóng.
- Database: **1 connection**, mọi truy cập qua `DispatchQueue(label: "exv.db")` `.sync`. Không giữ queue này khi đang stream file.
- Worker xử lý upload hoàn tất: `DispatchQueue(label: "exv.process", qos: .utility)` **serial** (đảm bảo tối đa 1 tác vụ nén cùng lúc).

## 6. Ngân sách tài nguyên (phải tuân thủ)

| Mục | Giới hạn |
|---|---|
| Buffer mỗi kết nối | 64KB (cấp phát 1 lần/kết nối) |
| Header HTTP | tối đa 16KB, tối đa 64 header |
| Body JSON | tối đa 1MB |
| Body khối upload | stream thẳng ra đĩa, không giữ trong RAM |
| Thumbnail upload | tối đa 256KB |
| SQLite cache | `PRAGMA cache_size=-2000` (2MB), `mmap_size=0`, `temp_store=FILE` |
| Ring log | 200 dòng |
| Phiên đăng nhập | tối đa 3 |
| Dung lượng trống tối thiểu | `reserveFreeBytes` (300MB), dưới mức này từ chối upload (`507`) |
| Timeout socket | đọc 30s, keep-alive idle 15s |

## 7. Đường dẫn dữ liệu

Xem `docs/02-data-model.md` mục 4. Thư mục dữ liệu bị loại khỏi backup (`isExcludedFromBackup = true`).

## 8. Điều KHÔNG làm

Không HTTPS, không WebSocket, không mDNS (có thể thêm sau), không đa tài khoản, không chia sẻ link, không transcode, không phân quyền.
