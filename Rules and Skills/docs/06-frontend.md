# 06 — Giao diện web (`Web/`)

Chỉ HTML/CSS/JS thuần (ES2017, không module bundler, không framework, không CDN, không font ngoài). Trình duyệt mục tiêu: Chrome/Edge/Firefox/Safari bản mới trên PC & điện thoại. Các script nạp bằng thẻ `<script defer src>` theo thứ tự trong `index.html`, dùng một namespace toàn cục `EX`.

## 1. Giao diện

- **Màu** (CSS variables trên `:root`, đổi bằng `html[data-theme="dark"]`):
  - Light: nền `#f5f0e1` (trắng kem), panel `#fbf8ee`, chữ `#111111`, viền `#d8d0b8`, nhấn `#111111` (nút chính nền đen chữ kem).
  - Dark: nền `#111111`, panel `#1a1a1a`, chữ `#f5f0e1`, viền `#333333`, nhấn `#f5f0e1`.
  - Mặc định theo `prefers-color-scheme`; người dùng đổi thì lưu `localStorage['exv.theme']` (`light|dark|auto`).
- **Font**: `font: 14px/1.4 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif`; tên file `13px`. Responsive: ≥ 900px có sidebar; < 900px sidebar thu thành menu (nút ☰).
- Bố cục kiểu MEGA/MediaFire:
  - **Topbar**: logo chữ "ExVault", ô tìm kiếm, nút đổi view (lưới/danh sách), nút ngôn ngữ (VI/EN), nút theme (◐), nút Đăng xuất.
  - **Sidebar**: "Tất cả file", danh sách Nhãn (kèm chấm màu, bấm để lọc), "Thùng rác", thanh dung lượng (đĩa còn trống + đã dùng thực + tỉ lệ nén: "Đã lưu 1.2 GB thay cho 1.9 GB (−37%)").
  - **Khu chính**: breadcrumb, toolbar (Tải lên, Thư mục mới, và khi có chọn: Tải về, Đổi tên, Di chuyển, Gắn nhãn, Xóa), danh sách/lưới.
  - **Panel upload** nổi góc dưới phải: mỗi file một dòng (tên, %, tốc độ, trạng thái, nút hủy), thu gọn được.
- **Hiển thị** (tùy biến ảnh/video): chế độ lưới có 3 cỡ ô (S 96px / M 160px / L 240px) lưu `localStorage['exv.gridSize']`; chọn "vừa khung" hoặc "cắt vuông" (`object-fit: contain|cover`, lưu `exv.fit`); danh sách có cột Tên, Nhãn, Kích thước (kèm kích thước nén nếu codec zlib, ví dụ `1.9 MB → 1.2 MB`), Ngày sửa. Sắp xếp bằng bấm tiêu đề cột (name/size/date/type).
- Đa ngôn ngữ: `vi` (mặc định theo `navigator.language` bắt đầu bằng `vi`) và `en`. Lưu `exv.lang`.

## 2. Module JS (đúng tên hàm)

**`util.js`**: `EX.$ (sel, root)`, `EX.h(tag, attrs, ...children)` (tạo DOM, **không** dùng innerHTML với dữ liệu người dùng; mọi text qua `textContent`), `EX.fmtBytes(n)`, `EX.fmtDate(ms)`, `EX.debounce(fn, ms)`, `EX.ext(name)`, `EX.isImage(node)`, `EX.isVideo(node)`, `EX.isPdf(node)`, `EX.isText(node)` (mime `text/*`, json, xml, hoặc đuôi md/log/csv...), `EX.toast(msg, kind)`.

**`i18n.js`**: `EX.t(key, vars)`, `EX.setLang(code)`, `EX.lang`. Hai bảng `vi` và `en` có **cùng tập khóa** (test bằng script Node đơn giản trong CI: so khóa hai bảng; script nằm ở `scripts/check-i18n.js`, chạy với `node` có sẵn trên runner).

**`api.js`**: bọc `fetch` với `credentials:'same-origin'`.
`EX.api.get(path)`, `post(path, body)`, `patch`, `del`, `put(path, blob)`; trả JSON; lỗi ném `EX.ApiError {status, code, message, extra}`. Gặp `401` ở bất kỳ call nào (trừ login) ⇒ phát sự kiện `EX.onUnauthorized()` ⇒ hiện màn đăng nhập. Hàm cụ thể: `login(u,p)`, `logout()`, `me()`, `stats()`, `listNodes(parent, sort, order)`, `getNode(id)`, `createFolder(parentId,name)`, `rename(id,name)`, `move(ids,parentId)`, `trash(ids)`, `restore(ids)`, `purge(ids)`, `listTrash()`, `emptyTrash()`, `search(q, tagId)`, `listTags()`, `createTag(name,color)`, `updateTag(id,patch)`, `deleteTag(id)`, `tagNodes(ids,add,remove)`, `contentUrl(id, dl)`, `thumbUrl(id)`, `putThumb(id, blob)`, `zipDownload(ids)` (tạo `<form method=POST action=/api/zip target=_self>` ẩn với input `ids`, submit, xóa form).

**`state.js`**: `EX.state = { user, parent:null|id, path:[], items:[], sort:'name', order:'asc', view:'list'|'grid', selection:Set, mode:'files'|'trash'|'search'|'tag', query:'', tagId:null, tags:[], stats:null }`; `EX.setState(patch)` + `EX.render()`; `EX.navigate(parentId)` (cập nhật `location.hash = '#/f/<id|root>'`, nạp lại), `EX.reload()`. Điều hướng bằng hash để nút Back hoạt động. Hash ghi `#/f/<id>` thư mục, `#/trash`, `#/tag/<id>`, `#/search/<q>`.

**`view.js`** (render danh sách/lưới, chọn, menu chuột phải, thao tác hàng loạt):
`renderTopbar()`, `renderSidebar()`, `renderBreadcrumb()`, `renderToolbar()`, `renderItems()`, `renderItem(node)`, `toggleSelect(id, {ctrl,shift})` (Shift chọn dải, Ctrl/Cmd thêm, bấm checkbox thêm), `selectAll()`, `clearSelection()`, `openContextMenu(x,y,node)` (Mở, Tải về, Đổi tên, Di chuyển, Gắn nhãn, Xóa; ở thùng rác: Khôi phục, Xóa vĩnh viễn), `promptRename(node)` (đổi tên tại chỗ bằng input, Enter lưu, Esc hủy, bôi đen phần tên không gồm đuôi), `openMoveDialog(ids)` (cây thư mục chọn đích; nạp lười từng cấp bằng `listNodes`), `openTagDialog(ids)` (checkbox các tag, thêm tag mới, đổi màu), `confirmDialog(msg)`, `bulkTrash()`, `bulkDownload()`.
Phím tắt: `Delete` xóa vào thùng rác, `F2` đổi tên, `Ctrl+A` chọn tất cả, `Esc` bỏ chọn/đóng, `Enter` mở. Kéo-thả file từ máy vào vùng chính ⇒ upload; kéo item vào thư mục ⇒ di chuyển.
Danh sách có thể có tới vài nghìn mục: dùng **render theo cụm** (`requestAnimationFrame`, mỗi frame 200 phần tử) hoặc cửa sổ ảo hóa đơn giản; **thumbnail nạp lười** bằng `IntersectionObserver` (`img.loading='lazy'` + `decoding='async'`) để không dồn request lên iPhone (client giới hạn song song 4 request thumbnail).

**`upload.js`**: xem `tasks/T15`. Hàm: `EX.upload.enqueue(files, parentId)`, `startNext()`, `uploadOne(job)`, `sendChunks(job)`, `finishAndPoll(job)`, `cancel(job)`, `makeThumb(file)`, `maybeCompressImage(file, opts)`, `renderPanel()`. Tối đa **2** upload song song (1 khi mạng chậm), mỗi upload tuần tự từng khối 4MB (`chunkSize` lấy từ `/api/me`). Khối lỗi mạng ⇒ thử lại tối đa 5 lần (chờ 1s, 2s, 4s, 8s, 16s); `409 offset_mismatch` ⇒ lấy `extra.offset` hoặc `GET /api/upload/:id` rồi tiếp tục từ offset đó. Đo tốc độ trung bình 5 giây.

**`viewer.js`**: xem `tasks/T17`. `EX.viewer.open(nodeId, list)`, `close()`, `next()`, `prev()`, hỗ trợ ảnh (zoom bằng nút +/−/fit; kéo để di chuyển khi zoom), video (`<video controls preload="metadata" playsinline src=contentUrl>`), PDF (`<iframe src=contentUrl>`; nếu trình duyệt không hiển thị được thì nút Tải về), văn bản (`fetch` tối đa 512KB đầu bằng header `Range` khi raw, hiện trong `<pre>`; nếu dài hơn hiện thông báo "đã cắt"). Phím mũi tên, Esc.

**`app.js`**: khởi động: `EX.init()` ⇒ `api.me()`; 401 ⇒ `renderLogin()` (form user/mật khẩu, thông báo lỗi, đếm ngược khi `429`); thành công ⇒ nạp tags, stats, định tuyến hash.

## 3. Xử lý lỗi UI

- Mọi lỗi API ⇒ toast với `EX.t('err.'+code)` (có khóa i18n cho mọi mã trong `docs/03`), fallback `err.unknown`.
- Mất kết nối ⇒ banner "Mất kết nối tới ExVault" và tự thử lại mỗi 5 giây qua `GET /api/health`.
- Không bao giờ chèn tên file bằng `innerHTML`.

## 4. Nén phía client (tùy chọn, mặc định TẮT)

Ở menu Cài đặt (biểu tượng ⚙ ở topbar): "Nén ảnh JPEG trước khi tải lên" (bật/tắt, `exv.imgCompress`), "Cạnh dài tối đa" (1280/1920/2560/Giữ nguyên, mặc định 2560), "Chất lượng" (0.7/0.8/0.85, mặc định 0.82). Chỉ áp dụng cho `image/jpeg`; chỉ dùng kết quả nếu nhỏ hơn bản gốc ít nhất 10%; cảnh báo: mất EXIF. PNG/GIF/HEIC/video không đụng tới.
