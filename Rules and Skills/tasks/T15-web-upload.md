# T15 — Web: upload chia khối, thumbnail, nén ảnh client

**Đọc**: `docs/06` mục 2 (`upload.js`), mục 4; `docs/03` mục Upload.

## File: `Web/js/upload.js` (+ chỉnh `view.js`/`app.js` để nối nút và kéo-thả)
```js
EX.upload = {
  queue: [], active: 0, maxParallel: 2,
  enqueue(files, parentId),           // File[] hoặc FileList; thư mục kéo-thả dùng webkitGetAsEntry duyệt đệ quy, tạo thư mục bằng createFolder theo thứ tự
  startNext(),
  async uploadOne(job),
  async sendChunks(job),              // PUT từng khối chunkSize, XHR hoặc fetch + AbortController
  async finishAndPoll(job),           // POST finish, poll GET /api/upload/:id mỗi 1s (tăng dần tới 3s) tới done|error
  cancel(job),                        // abort + DELETE /api/upload/:id
  async makeThumb(file),              // Blob JPEG ≤ 320px cạnh dài, quality 0.7; null nếu không làm được
  async maybeCompressImage(file),     // theo docs/06 mục 4
  renderPanel()
}
```
- `job = {id, file, parentId, name, size, state:'queued|compressing|uploading|processing|done|error|canceled', sent, uploadId, speed, error}`.
- Tiến độ: dùng `XMLHttpRequest.upload.onprogress` cho khối hiện tại (để thanh tiến độ mượt), cộng với phần đã gửi.
- Thử lại: 5 lần lùi mũ (1s…16s) khi lỗi mạng/5xx; `409 offset_mismatch` ⇒ nhảy tới `extra.offset`; `401` ⇒ dừng toàn bộ hàng đợi, giữ lại job.
- `429`/`503` ⇒ chờ 2s thử lại.
- Thumbnail: ảnh ⇒ `createImageBitmap`/`<img>` + canvas; video ⇒ `<video muted preload=metadata>` đặt `currentTime=min(1, duration/10)`, vẽ vào canvas (timeout 8s, lỗi ⇒ bỏ). Sau khi `done`, `PUT /api/files/:id/thumb`. Lỗi thumbnail **không** làm hỏng upload.
- Panel: tổng tiến độ, tốc độ, nút hủy từng file/tất cả, nút xóa dòng đã xong, tự đóng sau 5s khi tất cả xong (người dùng có thể mở lại). Sau mỗi job xong ⇒ `EX.reload()` nhưng gộp (debounce 500ms).
- Cảnh báo trước khi đóng tab nếu còn job đang chạy (`beforeunload`).
- Tên file lấy từ `file.name`; với thư mục kéo vào dùng đường dẫn tương đối để tạo thư mục con.

## Kiểm tra
Thủ công với CLI: upload nhiều file lớn (≥ 100MB), tắt/bật mạng giữa chừng (hoặc dừng CLI vài giây rồi chạy lại **cùng thư mục data**: upload `receiving` phải tiếp tục được; vì sessions mất khi server tắt, UI phải hiện màn đăng nhập rồi **tiếp tục** hàng đợi sau khi đăng nhập lại), hủy, thư mục lồng, file 0 byte, tên có dấu/emoji, ảnh JPEG lớn có bật nén.

## Nghiệm thu
- [ ] Mỗi khối là 1 request, không giữ cả file trong RAM trình duyệt (dùng `file.slice`). [ ] Thumbnail hiện sau khi upload. [ ] Hủy xóa `.part` phía server.
