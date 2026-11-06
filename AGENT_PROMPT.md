# AGENT_PROMPT — ExVault

Bạn là coding agent xây **ExVault**: app iOS (Swift 5, iOS 12.0+) chạy web server lưu trữ file trong LAN. Người giao việc **không biết code**; mọi quyết định đã nằm trong tài liệu. Hãy đọc `README.md` và toàn bộ `docs/` **trước khi viết bất kỳ dòng code nào**. Sau đó chỉ làm đúng **một task** trong `tasks/` mỗi lần.

## Luật bắt buộc

1. **Không thêm tính năng** ngoài tài liệu. Không link chia sẻ, không admin, không transcode video, không đồng bộ, không ghi log ra đĩa.
2. **Không thư viện ngoài** (không SwiftPM dependency, không CocoaPods, không npm, không CDN). Web chỉ dùng HTML/CSS/JS thuần, không framework, không file font ngoài.
3. **Cấm API iOS ≥ 13**: không `async/await`, `Task`, `actor`, Combine, SwiftUI, `UIScene`/SceneDelegate, `UIColor.systemBackground`, `JSONEncoder.OutputFormatting.withoutEscapingSlashes`, `URLSession` async. Dùng GCD (`DispatchQueue`, `DispatchSemaphore`), `UIKit` viết tay, `AppDelegate` có `window`.
4. **Không đọc nguyên file lớn vào RAM**: file blob luôn đọc/ghi bằng POSIX `open/read/pread/write/close` với buffer 64KB. Cấm `Data(contentsOf:)`, `FileManager.contents(atPath:)` cho blob/upload.
5. **Ngân sách RAM server < 80MB** ở trạng thái thường. Không cache ảnh/thumbnail trong RAM. Tối đa 8 kết nối đồng thời.
6. **Không `try!`, `fatalError`, force unwrap `!`** trong code server (trừ literal hằng chắc chắn). Mọi lỗi phải trả về JSON lỗi theo `docs/03-api.md`.
7. **Không bao giờ để SQL ghép chuỗi từ input người dùng**. Luôn bind tham số.
8. **Chống path traversal**: client không bao giờ gửi đường dẫn file hệ thống; chỉ dùng id. File tĩnh phải qua `StaticFiles.resolve`.
9. Tên hàm, tên file, chữ ký, mã lỗi, tên cột, tên endpoint: **dùng đúng như tài liệu**. Nếu thấy tài liệu mâu thuẫn hoặc thiếu, **dừng lại và hỏi người giao việc**, ghi vào `PROGRESS.md` mục "Câu hỏi mở". Không tự đoán.
10. Mọi comment trong code bằng tiếng Anh, ngắn. Chuỗi giao diện người dùng đi qua i18n (vi/en).

## Quy trình mỗi task

1. Đọc file task + các doc nó trỏ tới.
2. Viết code theo đúng "Danh sách file" và "Logic" trong task.
3. Viết/cập nhật unit test được yêu cầu (thư mục `Tests/ExVaultCoreTests`).
4. Commit với tin nhắn `T<nn>: <tóm tắt>` rồi push. CI (`.github/workflows/build.yml`) phải **xanh**. Bạn không có Mac nên **CI là cách duy nhất để biên dịch/chạy test**; nếu không có `gh` CLI thì nhờ người giao việc dán log lỗi.
5. Tự kiểm tra từng dòng "Tiêu chí nghiệm thu"; tick trong `PROGRESS.md`. Chưa xanh hoặc chưa tick đủ thì **không** sang task khác.
6. Cuối task, báo cáo ngắn: file đã tạo/sửa, test đã chạy, điểm còn nghi ngờ.

## Định nghĩa "xong"

- CI xanh (build + test + integration script nếu đã có).
- Không cảnh báo biên dịch mới liên quan tới availability (`is only available in iOS 13.0 or newer` = lỗi, phải sửa).
- Không file nào thừa, không TODO còn sót, không code chết.

## Quy ước chung

- Ngôn ngữ: Swift 5 (`SWIFT_VERSION=5.0`), tools-version 5.5.
- Thời gian lưu trong DB: Unix epoch **mili-giây** (`Int64`).
- JSON: `camelCase`. Kích thước: byte (`Int64`).
- ID node/blob/upload/session: chuỗi hex thường, 24 ký tự (12 byte ngẫu nhiên) — xem `IDGen`.
- Mọi lỗi HTTP trả `Content-Type: application/json; charset=utf-8` với dạng `{"error":{"code":"...","message":"..."}}`.
- Log qua `Log.info/warn/error`, chỉ ra stdout + ring buffer RAM 200 dòng.
