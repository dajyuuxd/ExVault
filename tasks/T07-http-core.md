# T07 — HTTP server core

**Đọc**: `docs/05` mục 1–2, `docs/01` mục 5–6.

## File: `Http/HttpTypes.swift`, `Http/HttpServer.swift`
Cài đúng mô tả. Chi tiết:
- `start(port:)`: nếu `port == 0` ⇒ để hệ điều hành chọn, đọc cổng thật bằng `getsockname` (dùng cho test); ngược lại thử `port...port+10`.
- `stop()`: đóng listening fd (`shutdown` + `close`) để `accept` thoát; đặt cờ dừng.
- Parser viết tay trên buffer `[UInt8]` 64KB cấp một lần cho mỗi kết nối; tìm `\r\n\r\n` bằng quét byte. Header tên nhiều dòng (obs-fold) không hỗ trợ ⇒ `400`.
- `BodyReader` nhận phần body đã đọc dư khỏi buffer đầu rồi mới đọc tiếp socket.
- Ghi response: gom header vào một `Data` rồi `write`; body stream gọi `writer.write` (ghi trực tiếp socket); chunked: mỗi lần ghi `"<hex>\r\n"+data+"\r\n"`, kết thúc `0\r\n\r\n`.
- Dùng `ResponseWriter` cài trên lớp `SocketWriter` (có `fd`, đếm byte). Lỗi ghi ⇒ ném `SocketError.closed`.
- Mã trạng thái cần câu chữ: 200 OK, 201 Created, 202 Accepted, 204 No Content, 206 Partial Content, 304 Not Modified, 400, 401, 404, 405, 409, 411, 413, 416, 429, 431, 500, 503, 507.

## Test: `HttpServerTests.swift` (handler echo trong test, `URLSession` + semaphore)
GET trả JSON; POST body 1MB echo độ dài; HEAD không body; keep-alive: 2 request trên cùng socket (dùng socket thô trong test để đếm); header > 16KB ⇒ 431; method lạ ⇒ 405; `Transfer-Encoding: chunked` từ client ⇒ 411; handler stream có `length=nil` ⇒ client nhận đủ (chunked); 20 kết nối cùng lúc khi `maxConnections=2` ⇒ một số nhận `503`, không treo; client ngắt giữa chừng khi tải stream lớn ⇒ server không crash, request tiếp theo vẫn chạy; `stop()` rồi `start()` lại trên cổng khác.

## Nghiệm thu
- [ ] Test xanh, không flaky (chạy 3 lần). [ ] `SIGPIPE` bị bỏ qua. [ ] Không đọc quá `Content-Length`.
