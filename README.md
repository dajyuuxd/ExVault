# ExVault — Bộ tài liệu cho coding agent

ExVault là app iOS (file `.ipa`) biến iPhone cũ (mục tiêu đầu tiên: **iPhone 5s, iOS 12.5.8, đã jailbreak**) thành máy chủ lưu trữ kiểu MediaFire/MEGA chạy **offline trong mạng LAN**. Mở app → app tự chạy web server, hiện sẵn tên đăng nhập + mật khẩu của phiên đó → vào `http://<IP-iPhone>:8080` từ máy tính/điện thoại khác để upload, duyệt, xem ảnh/video (streaming), tải về.

## 1. Quyết định đã chốt

| Hạng mục | Quyết định |
|---|---|
| Hình thức | App iOS native `.ipa`, **Swift 5, không thư viện bên thứ ba**, không storyboard (trừ LaunchScreen) |
| iOS tối thiểu | **12.0** (để chạy 5s). Cấm API từ iOS 13 trở lên (async/await, Combine, SwiftUI, `Task`...) |
| Build | **GitHub Actions** (runner macOS) vì bạn dùng Windows. Không cần Mac |
| Cấu trúc code | `ExVaultCore` (server, không UIKit) dùng chung cho app iOS **và** CLI macOS để test tự động trên CI |
| Server | Tự viết HTTP/1.1 trên socket POSIX, thread có giới hạn, stream 64KB |
| Lưu trữ | File blob trên đĩa + SQLite (metadata). Không đọc nguyên file vào RAM |
| Nén | zlib (Apple Compression framework) cho file nén được; ảnh/video giữ nguyên bản gốc. Tùy chọn nén ảnh JPEG phía trình duyệt trước khi upload |
| Video | Không transcode. Stream bản gốc bằng HTTP Range |
| Đăng nhập | Mỗi lần mở server sinh user + mật khẩu ngẫu nhiên, hiện trên màn hình iPhone. Cookie phiên. Tối đa 3 phiên |
| Dữ liệu | 1 kho dùng chung, giữ nguyên giữa các lần chạy lại |
| Mạng | HTTP, cổng 8080 (tự thử 8081–8090 nếu bận) |
| Giao diện web | HTML/CSS/JS thuần, nền kem + chữ đen, có dark mode, vi/en |
| Tính năng | Thư mục, upload chia khối (resume), đổi tên, di chuyển, chọn nhiều, nhãn, tìm kiếm, thùng rác, tải zip, xem trước, thống kê dung lượng. **Không** có link chia sẻ, **không** admin |
| Giữ máy sống | `idleTimerDisabled` + phát âm thanh im lặng (UIBackgroundModes=audio) + chế độ làm tối màn hình |
| Log | Chỉ hiện trên màn hình/console, **không ghi ra đĩa** |

## 2. Việc của bạn (người không code)

1. Tạo tài khoản GitHub, cài **Git for Windows**, tạo repo trống tên `ExVault` (nên để *public* để GitHub Actions macOS miễn phí không giới hạn phút; repo private bị tính phút và macOS tính phút gấp 10).
2. Giải nén bộ tài liệu này vào thư mục repo, `git add . && git commit && git push`.
3. Mở thư mục repo trong **Antigravity**, dán nội dung `AGENT_PROMPT.md` làm chỉ dẫn gốc, rồi giao **một task một lần**: *"Làm task `tasks/T00-scaffold-ci.md`"*.
4. Sau mỗi task agent push code → vào tab **Actions** trên GitHub xem xanh/đỏ. Nếu đỏ, copy log lỗi đưa lại cho agent. Nếu agent dùng được `gh` CLI thì nó tự xem log.
5. Chỉ chuyển sang task kế khi task trước **xanh** và agent đã tick đủ tiêu chí nghiệm thu trong `PROGRESS.md`.
6. Sau T18 (CI xuất file `.ipa`): tải artifact `ExVault-unsigned.ipa` ở tab Actions, cài lên 5s đã jailbreak (cần AppSync Unified hoặc cài bằng Filza/ipainstaller; bước này bạn tự xử lý).
7. Mở app trên iPhone → đọc user/mật khẩu → vào địa chỉ hiển thị bằng trình duyệt máy tính.

## 3. Danh mục tài liệu

| File | Nội dung |
|---|---|
| `AGENT_PROMPT.md` | Prompt gốc + luật bắt buộc cho agent |
| `PROGRESS.md` | Bảng theo dõi tiến độ, agent tự cập nhật |
| `docs/01-architecture.md` | Kiến trúc, cấu trúc thư mục, API công khai của core, luồng, ngân sách RAM |
| `docs/02-data-model.md` | Schema SQLite, quy tắc tên, thùng rác, cấu trúc thư mục dữ liệu |
| `docs/03-api.md` | Toàn bộ endpoint, JSON, mã lỗi |
| `docs/04-storage-compression.md` | Upload chia khối, chính sách nén, hàm nén stream, tải về, Range, ZIP |
| `docs/05-http-auth.md` | HTTP server, router, xác thực, giới hạn |
| `docs/06-frontend.md` | Giao diện web, module JS, hành vi |
| `docs/07-ios-app-ci.md` | App iOS, KeepAlive, Info.plist, XcodeGen, CI, đóng gói IPA |
| `tasks/T00…T19` | 20 task nhỏ, làm tuần tự, có tiêu chí nghiệm thu |

## 4. Rủi ro cần biết trước

1. **iOS 12.0 + Xcode trên CI**: Xcode 15.x còn hỗ trợ deployment target iOS 12.0. Nếu runner đổi phiên bản Xcode làm build lỗi, chọn Xcode khác bằng `xcode-select` (xem `docs/07`).
2. **IPA không ký**: chỉ chạy được trên máy jailbreak có công cụ cho phép cài/ chạy app không ký (AppSync Unified...). Ngoài phạm vi tài liệu này.
3. **iOS có thể kill app nền**: đã giảm rủi ro bằng audio im lặng và `idleTimerDisabled`, nhưng không có gì tuyệt đối. Cách chắc nhất là để app luôn ở foreground, cắm sạc, màn hình tối.
4. **Dung lượng**: 16GB trừ hệ điều hành thường còn khoảng 6–9GB trống.
5. **CPU A7 yếu**: nén zlib khoảng vài chục MB/s ở mức tốt nhất, nên nén chạy nền 1 luồng, upload hoàn tất sẽ có trạng thái "đang xử lý".
6. **ZIP**: bản đầu không hỗ trợ ZIP64, giới hạn mỗi lần tải zip < 4GB và < 65535 mục.
