# T16 — Web: chọn nhiều, đổi tên, di chuyển, nhãn, thùng rác, tìm kiếm, menu

**Đọc**: `docs/06` mục 2 (`view.js`), `docs/03`.

## File: mở rộng `Web/js/view.js`, `state.js`, `app.js`, `css/app.css`
Cài đủ các hàm `docs/06` mục 2 cho `view.js`: chọn (checkbox, Shift/Ctrl, Ctrl+A), menu chuột phải (và bấm giữ 500ms trên màn cảm ứng), đổi tên tại chỗ, `openMoveDialog` (cây thư mục nạp lười, không cho chọn chính nó/hậu duệ khi di chuyển thư mục), `openTagDialog`, `bulkTrash`, `bulkDownload` (1 file ⇒ link `content?dl=1`; nhiều/thư mục ⇒ `zipDownload`), kéo item vào thư mục để di chuyển, phím tắt.
- Chế độ thùng rác: danh sách `listTrash`, thao tác Khôi phục, Xóa vĩnh viễn, Dọn sạch (xác nhận).
- Tìm kiếm: ô topbar debounce 300ms ⇒ `search`; kết quả hiện kèm `pathText`, bấm vào "mở thư mục chứa". Bấm nhãn ở sidebar ⇒ `search(null, tagId)`.
- Nhãn: hiển thị chấm màu cạnh tên; quản lý nhãn (đổi tên, đổi màu, xóa) trong dialog.
- Sau mỗi thao tác: cập nhật cục bộ + `EX.reload()` khi cần; `stats` làm mới sau upload/xóa.
- Hiển thị: nút cỡ lưới S/M/L, chế độ vừa khung/cắt vuông; thumbnail nạp lười giới hạn 4 request song song; item không có thumbnail dùng icon theo loại.
- Dialog tự dựng (không dùng `alert/confirm/prompt` của trình duyệt), đóng bằng Esc, trap focus cơ bản.

## Kiểm tra thủ công
Chọn 50 file bằng Shift ⇒ di chuyển ⇒ gắn nhãn ⇒ tải zip ⇒ xóa ⇒ khôi phục. Đổi tên trùng hiện toast `err.name_conflict`. Tìm tên có dấu. 2000 file trong 1 thư mục cuộn mượt trên điện thoại.

## Nghiệm thu
- [ ] Mọi thao tác có thông báo lỗi i18n. [ ] Không dùng `alert/confirm/prompt`. [ ] i18n check xanh.
