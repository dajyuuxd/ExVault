# T14 — Web: khung, đăng nhập, i18n, theme, danh sách

**Đọc**: `docs/06` mục 1–3, `docs/03`.

## File: `Web/index.html`, `Web/css/app.css`, `Web/js/util.js`, `i18n.js`, `api.js`, `state.js`, `view.js` (phần cơ bản), `app.js`, và `scripts/check-i18n.js`
- `index.html`: `<meta name="viewport" content="width=device-width,initial-scale=1">`, `<link rel=stylesheet href=css/app.css>`, các `<script defer>` theo thứ tự `util, i18n, api, state, upload(rỗng ở task này), view, viewer(rỗng), app`. Một `<div id="app">`. **Không** script inline (dễ kiểm soát).
- `app.css`: biến màu 2 theme (`docs/06` mục 1), layout flex/grid, breakpoint 900px, ô lưới `grid-template-columns: repeat(auto-fill, minmax(var(--cell), 1fr))`, trạng thái chọn, toast, dialog, focus ring rõ ràng. Không ảnh/font ngoài; icon bằng ký tự Unicode (📁 📄 🖼 🎞) hoặc SVG inline nhỏ.
- `util.js`, `i18n.js`, `api.js`, `state.js`: đúng tên hàm `docs/06` mục 2. Bảng i18n phải có khóa cho: mọi nhãn UI, mọi mã lỗi `err.<code>`, `err.unknown`, đơn vị.
- `view.js` (task này): `renderTopbar`, `renderSidebar` (mục Tất cả file, Nhãn, Thùng rác, dung lượng), `renderBreadcrumb`, `renderItems` (list + grid, chưa có thumbnail/menu), mở thư mục bằng bấm đôi/Enter, sắp xếp bằng tiêu đề cột, đổi view, đổi theme/ngôn ngữ.
- `app.js`: `EX.init`, màn đăng nhập (`renderLogin`), xử lý `429` có đếm ngược, định tuyến hash.
- `scripts/check-i18n.js`: Node thuần, `vm` chạy `Web/js/i18n.js` với `window` giả, so khóa `vi` vs `en`, exit 1 nếu lệch.

## Kiểm tra (CI + thủ công)
- CI: `node scripts/check-i18n.js` xanh; integration script: `GET /js/app.js` = 200.
- Thủ công (ghi vào PROGRESS cách người dùng kiểm): chạy CLI trên máy, mở trình duyệt, đăng nhập, tạo thư mục (nếu API đã có), đổi theme/ngôn ngữ, F5 giữ trạng thái, nút Back chạy đúng.

## Nghiệm thu
- [ ] Không có `innerHTML` với dữ liệu người dùng (grep). [ ] Hai bảng i18n khớp khóa. [ ] Giao diện dùng được ở 360px và 1280px. [ ] Không request tới tên miền ngoài.
