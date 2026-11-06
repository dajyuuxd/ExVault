# T10 — API: auth, nodes, tags, trash, search, stats + VaultServer

**Đọc**: `docs/03`, `docs/01` mục 4–5, `docs/05`.

## File: `Api/ApiContext.swift`, `Api/AuthApi.swift`, `Api/NodesApi.swift`, `Api/TagsApi.swift`, `Api/StatsApi.swift`, `VaultServer.swift` (thay bản stub của T00)

```swift
final class ApiContext {
    let config: VaultConfig; let credentials: Credentials
    let db: Database; let store: VaultStore; let blobs: BlobStore; let uploads: UploadManager
    let sessions: SessionStore; let limiter: RateLimiter; let static: StaticFiles
    func json<T: Decodable>(_ req: HttpRequest, _ type: T.Type) throws -> T   // readAll(limit: 1MB) + decode; lỗi ⇒ ApiError bad_request
    func nodeJSON(_ n: Node) -> HttpResponse ...
}
protocol ApiModule { static func register(_ r: Router, _ ctx: ApiContext) }
enum AuthApi: ApiModule { … }   // health, login, logout, me
enum NodesApi: ApiModule { … }  // nodes list/get, folders, rename, move, trash, restore, purge, trash list/empty, search, nodes/tag
enum TagsApi: ApiModule { … }
enum StatsApi: ApiModule { … }
```
- `VaultServer.init(config:)`: tạo thư mục `dataDir`; `Database(path: dataDir/vault.db)`; `BlobStore`; `VaultStore`; `UploadManager` (+ `cleanupAtStartup()`); `Credentials.generate()`; `SessionStore`; `RateLimiter`; `StaticFiles(root: webRoot)`; `Router` đăng ký mọi module (UploadApi/FilesApi/ZipApi đăng ký sau ở T11/T12: để `register` của chúng nằm trong mảng modules, thêm dần). Đặt `isExcludedFromBackup`.
- `start()`: `HttpServer.start(port:)` ⇒ gán `boundPort`; `Log.info("listening on …")`.
- Đăng ký route tĩnh: `GET /` và `GET /css/:file`, `GET /js/:file` (Router hỗ trợ tham số 1 segment; `StaticFiles.serve` nhận `req.path`).
- `purge` / `emptyTrash`: gọi store ⇒ sau commit gọi `blobs.delete(blobId:)`, `blobs.deleteThumb(nodeId:)`.
- Mọi handler dùng `ctx.store` và dịch `StoreError`→`ApiError` qua router (đã có ở T08).
- Giới hạn `ids.count <= 5000` ⇒ `bad_request`.
- `GET /api/nodes?parent=root|id`: `parent` không phải `root` mà không tồn tại/trashed ⇒ `404`. Trả `path`, `parent {id,name}`, `items`.
- `/api/me` trả `chunkSize` (từ config) và `limits.maxZipBytes = 4294967295`.
- `/api/stats` cộng `diskFree/diskTotal` từ `BlobStore`, tính `ratio`.

## Test: `ApiCoreTests.swift` (server thật trên cổng 0, dùng `URLSession` + cookie)
Login sai ⇒ 401, 6 lần sai ⇒ 429 có `Retry-After`; không cookie ⇒ 401; login đúng ⇒ cookie `HttpOnly; SameSite=Strict`; `GET /` không cần login; tạo thư mục, liệt kê, đổi tên trùng ⇒ 409, move vòng ⇒ 400 `invalid_move`; trash/restore/purge; tag CRUD + gắn tag; search; stats; logout rồi gọi lại ⇒ 401; vượt 3 phiên ⇒ phiên cũ nhất bị 401; JSON hỏng ⇒ 400; body > 1MB ⇒ 413.

## Nghiệm thu
- [ ] Test xanh. [ ] Mọi endpoint trong `docs/03` mục Auth/Node/Tag/stats đều có test gọi qua HTTP.
