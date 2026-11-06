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
| T14 | Web: shell, login, i18n, theme, danh sách | ☐ | | |
| T15 | Web: upload chia khối, thumbnail, nén ảnh client | ☐ | | |
| T16 | Web: chọn nhiều, đổi tên, nhãn, thùng rác, tìm kiếm, menu | ☐ | | |
| T17 | Web: xem trước ảnh/video/pdf/text | ☐ | | |
| T18 | App iOS + KeepAlive + đóng gói IPA | ☐ | | |
| T19 | Rà soát & tối ưu (tùy chọn) | ☐ | | |

## Câu hỏi mở
(không có)
