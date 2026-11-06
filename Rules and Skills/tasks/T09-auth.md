# T09 — Auth

**Đọc**: `docs/05` mục 6.

## File: `Auth/Credentials.swift`, `Auth/SessionStore.swift`, `Auth/RateLimiter.swift`
Cài đúng chữ ký. Thêm tham số `now: @escaping () -> Date = Date.init` vào `SessionStore` và `RateLimiter` để test điều khiển thời gian.

## Test: `AuthTests.swift`
Credentials: độ dài 5/8, chỉ ký tự cho phép, 200 lần sinh không trùng nhau toàn bộ; Session: token 64 hex, vượt `max` loại phiên cũ nhất, hết hạn, gia hạn khi validate, `destroy`; RateLimiter: 5 lần sai ⇒ bị khóa đúng `lockout`, hết khóa mở lại, `recordSuccess` xóa bộ đếm, IP khác không ảnh hưởng, giới hạn 256 IP không phình bộ nhớ; `constantTimeEquals` ca độ dài khác nhau.

## Nghiệm thu
- [ ] Test xanh. [ ] Không dùng `rand/random()`.
