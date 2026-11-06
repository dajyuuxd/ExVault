# T19 — Tối ưu và rà soát cuối (tùy chọn nhưng nên làm)

**Đọc**: `docs/01` mục 6.

1. Rà soát ngân sách tài nguyên: grep `Data(contentsOf`, `contents(atPath`, `try!`, `fatalError`, `!` ép giá trị, `innerHTML` ⇒ phải sạch.
2. Test tải: script `scripts/soak.sh` (chạy tay, không bắt buộc trên CI): upload 2GB bằng `curl` chia khối vào CLI, đo thời gian; 4 tải xuống song song; kiểm RSS tiến trình CLI (`ps -o rss`) không vượt ~80MB.
3. Kiểm tra mất điện giả lập: `kill -9` CLI giữa chừng upload ⇒ khởi động lại: `.part` được dọn đúng, DB mở được (WAL), `processing` ⇒ `error`.
4. Đọc `README.md` và cập nhật mục "Rủi ro" nếu có phát hiện mới.
