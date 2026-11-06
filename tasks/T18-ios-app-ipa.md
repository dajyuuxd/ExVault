# T18 — App iOS, KeepAlive, đóng gói IPA

**Đọc**: `docs/07` toàn bộ, `docs/01` mục 4.

## File: `App/AppDelegate.swift`, `App/ViewController.swift`, `App/KeepAlive.swift` (thay bản đơn giản của T00), chỉnh `project.yml`/workflow nếu cần
- Cài đúng các lớp ở `docs/07` mục 1–3. Không dùng API iOS ≥ 13 (trình biên dịch sẽ báo lỗi availability).
- `ViewController`:
  - `UIScrollView` + `UIStackView`, các `UILabel` `Menlo` 13pt (`numberOfLines = 0`, `lineBreakMode = .byCharWrapping`), nền đen.
  - Mật khẩu 22pt đậm; hai nút `Dim screen`, `Copy pass`.
  - `Timer` 1 giây cập nhật; hiển thị `(no network)` khi chưa có IP.
  - Nhận `VaultServer?` qua closure `serverProvider: () -> VaultServer?` để tránh chu trình giữ.
- Không dùng Auto Layout phức tạp: stack view neo 4 cạnh `safeAreaLayoutGuide` (iOS 11+ OK).
- `KeepAlive.makeSilentWav` có unit test chạy trên macOS: **đưa hàm này vào core** (`Sources/ExVaultCore/Util/SilentWav.swift`, `public enum SilentWav { public static func make(seconds: Int) -> Data }`) để test được; `KeepAlive` gọi hàm này. Test: độ dài `44 + 16000*seconds`, header `RIFF`/`WAVE`/`fmt `/`data`, mọi mẫu bằng 0.
- Khi `server.start()` lỗi (hết cổng) ⇒ hiện lỗi rõ ràng.

## CI
- Workflow đã có bước IPA (`docs/07` mục 6); kiểm lại: `MinimumOSVersion=12.0`, `arm64`, có `Web/index.html`, `Web/js/app.js` trong `.app`.
- Thêm bước in `du -sh` của `.app` và `.ipa` (kích thước mục tiêu < 2MB).

## Kiểm tra thủ công (người dùng, trên iPhone 5s)
Ghi checklist này vào `PROGRESS.md` cho người dùng:
1. Cài IPA, mở app: thấy user/pass/URL.
2. Từ PC cùng Wi-Fi mở URL, đăng nhập.
3. Upload 1 ảnh, 1 video ~100MB, 1 file `.txt`; xem ảnh; phát video, tua.
4. Để máy 30 phút không chạm: màn hình **không** khóa; vẫn truy cập được.
5. Bấm `Dim screen`: màn tối, server vẫn chạy; chạm để bật lại.
6. Thoát về Home (nếu muốn thử nền): ghi nhận server còn sống bao lâu.
7. Tắt app mở lại: user/pass **đổi**, dữ liệu **còn**.

## Nghiệm thu
- [ ] CI xanh, artifact IPA có. [ ] Test SilentWav xanh. [ ] Checklist thủ công đã được ghi cho người dùng.
