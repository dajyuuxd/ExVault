# PROGRESS

Agent cập nhật file này sau mỗi task. Chỉ tick khi CI xanh và đã tự kiểm tra từng tiêu chí.

| Task | Tên | Trạng thái | CI | Ghi chú |
|---|---|---|---|---|
| T00 | Scaffold + CI | ☑ | Xanh | Hoàn thành scaffold, CI core + ios xanh, sinh artifact IPA |
| T01 | Util (ID, CRC32, tên, MIME, Log) | ☑ | Xanh | 19 tests, toàn bộ util modules hoàn thành |
| T02 | SQLite wrapper + schema | ☑ | Xanh | Database wrapper, transactions, WAL mode, Schema v1 migration |
| T03 | VaultStore: nodes, thùng rác | ☑ | Xanh | Node hierarchy, sorting, CTE trash, purge, deadlock-free sync |
| T04 | VaultStore: tags, search, stats | ☑ | Xanh | Tags CRUD, LIKE escape search, vault statistics |
| T05 | BlobStore + Compressor | ☑ | Xanh | Sharded blob storage, streaming Apple zlib raw DEFLATE |
| T06 | UploadManager | ☑ | Xanh | Chunked upload, quota check, CRC32 verification, auto-compression, startup cleanup |
| T07 | HTTP server core | ☑ | Xanh | POSIX socket HTTP/1.1, keep-alive, streaming chunked, connection cap, SIGPIPE ignore |
| T08 | Router, Range, static files | ☑ | Xanh | URL routing with :id/wildcards, Range parser, StaticFiles with realpath traversal protection and ETag |
| T09 | Auth | ☑ | Xanh | Credentials generator, SessionStore with TTL & sliding window, RateLimiter with lockout & bounded IP table |
| T10 | API: nodes, folders, tags, trash, search, stats | ☑ | Xanh | ApiContext, AuthApi, NodesApi, TagsApi, StatsApi, VaultServer integration tested over HTTP |
| T11 | API: upload, content, thumb | ☑ | Xanh | Upload initiation/chunks/finish/cancel, content download (raw Range + zlib streaming), thumbnail PUT/GET |
| T12 | ZipWriter + endpoint | ☑ | Xanh | Stored ZIP archive streaming, VaultStore.zipEntries hierarchy, POST /api/zip, tested with macOS unzip -t |
| T13 | CLI macOS + integration script | ☑ | Xanh | CLI executable, curl integration test suite in CI with ALL PASSED |
| T14 | Web: shell, login, i18n, theme, danh sách | ☑ | Xanh | Web shell, login with rate limit countdown, symmetric i18n (vi/en), list/grid views, responsive design |
| T15 | Web: upload chia khối, thumbnail, nén ảnh client | ☑ | Xanh | 4MB chunked streaming upload with XHR progress & retry, client thumbnail generator (image/video), optional client JPEG compression |
| T16 | Web: chọn nhiều, đổi tên, nhãn, thùng rác, tìm kiếm, menu | ☑ | Xanh | Multi-selection (Shift/Ctrl/A), context menu & touch long-press, inline rename, tag CRUD, lazy move tree, cluster rendering |
| T17 | Web: xem trước ảnh/video/pdf/text | ☑ | Xanh | Full-screen lightbox previewer (zoom/pan, video connection release, audio, PDF, 512KB range text) |
| T18 | App iOS + KeepAlive + đóng gói IPA | ☑ | Xanh | Native iOS 12+ app, SilentWav in-memory keep-alive loop, Dim screen, dashboard, unsigned IPA artifact |
| T19 | Rà soát & tối ưu (tùy chọn) | ☑ | Xanh | Rà soát tài nguyên sạch (0 innerHTML, 0 Data(contentsOf), 0 try!, 0 fatalError), soak test script, README cập nhật rủi ro |

## Hướng dẫn kiểm tra thủ công trên iPhone (T18)
1. Cài IPA (`ExVault-unsigned.ipa` từ GitHub Actions Artifacts qua AltStore / Sideloadly / TrollStore), mở app: màn hình đen hiển thị Uptime, URL LAN, User, Password, Disk free, Sessions, và Log.
2. Từ máy tính hoặc thiết bị khác trong cùng mạng Wi-Fi, mở URL (vd: `http://192.168.1.x:8080`), đăng nhập bằng User/Pass trên màn hình iPhone.
3. Thử tải lên: 1 ảnh, 1 video dung lượng ~100MB, 1 file văn bản `.txt`; mở lightbox xem trước ảnh; phát video và tua timeline (kiểm tra HTTP Range 206).
4. Để điện thoại 30 phút không chạm: màn hình không bị tự động khóa; server vẫn duy trì kết nối ổn định.
5. Bấm nút `Dim screen`: màn hình tối hoàn toàn để tiết kiệm pin/chống lưu ảnh OLED, server vẫn chạy; chạm bất kỳ điểm nào trên màn hình để bật sáng lại.
6. Thoát về màn hình Home (nền): ghi nhận audio im lặng duy trì tiến trình nền.
7. Đóng ứng dụng (vuốt tắt trong App Switcher) và mở lại: User/Pass được tạo mới ngẫu nhiên; toàn bộ dữ liệu file đã tải lên vẫn nguyên vẹn.

## Câu hỏi mở
(không có)
