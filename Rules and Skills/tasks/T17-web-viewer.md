# T17 — Web: xem trước ảnh/video/pdf/text

**Đọc**: `docs/06` (`viewer.js`), `docs/04` mục 5.

## File: `Web/js/viewer.js`, CSS tương ứng
- Overlay toàn màn, nền gần đen, nút đóng/trước/sau/tải về/ thông tin (tên, kích thước, nén, ngày).
- `open(nodeId, list)`: `list` = các node cùng thư mục đang hiển thị mà xem được (ảnh/video/pdf/text), điều hướng ← → giữa chúng.
- Ảnh: `<img src=contentUrl>`; nút Fit/100%/Zoom ±, kéo để pan khi zoom, cuộn chuột để zoom, pinch trên cảm ứng (tối thiểu: double-tap chuyển Fit/100%). Nạp trước ảnh kế tiếp bằng `new Image()` (chỉ 1 ảnh).
- Video: `<video controls preload="metadata" playsinline>`; khi chuyển/đóng ⇒ `video.pause(); video.removeAttribute('src'); video.load()` để giải phóng kết nối với iPhone. Hiện thông báo nếu trình duyệt không phát được định dạng (`error` event) kèm nút Tải về. **Không** transcode.
- PDF: `<iframe src=contentUrl>`; lỗi/không hỗ trợ ⇒ nút Tải về.
- Văn bản: nếu `codec=raw` dùng `Range: bytes=0-524287`; nếu `zlib` tải rồi cắt 512KB đầu; hiện `<pre>` (textContent). Quá dài ⇒ chú thích "đã cắt, tải về để xem đủ".
- Đóng bằng Esc/nhấp nền; lưu `location.hash` dạng `#/v/<id>` (để F5 mở lại, tùy chọn).
- Slideshow/trình chiếu: **không làm**.

## Kiểm tra thủ công với CLI
Ảnh JPEG/PNG/GIF/WebP lớn; video MP4 (moov cuối file và moov đầu file) tua tới giữa phải chạy ngay (thấy request `206` trong log hoặc DevTools); PDF; `.md`/`.log`; chuyển qua lại 30 mục không treo; đóng video giữa chừng thì kết nối được trả lại.

## Nghiệm thu
- [ ] Video tua được (Range hoạt động). [ ] Không rò rỉ kết nối khi đóng video. [ ] Phím tắt hoạt động.
