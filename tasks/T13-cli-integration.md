# T13 — CLI macOS + integration script

**Đọc**: `docs/01` mục 4, `docs/07` mục 6.

## `Sources/exvault-cli/main.swift`
Tham số: `--data <dir>` (mặc định `./data`), `--web <dir>` (mặc định `./Web`), `--port <n>` (mặc định 8080). Tạo `VaultServer`, `start()`, in **đúng các dòng** (dùng cho script):
```
EXVAULT_URL=http://127.0.0.1:<port>
EXVAULT_USER=<username>
EXVAULT_PASS=<password>
EXVAULT_READY=1
```
rồi `RunLoop.main.run()` (hoặc `dispatchMain()`); bắt `SIGINT/SIGTERM` ⇒ `stop()`. In thêm mọi `Log` ra stdout.

## `scripts/integration.sh` (bash, `set -euo pipefail`, chạy trên macOS runner)
1. `swift build -c release`; tạo thư mục tạm; chạy `.build/release/exvault-cli --data $TMP/data --web Web --port 18080 > $TMP/out.log &`; chờ tới khi `EXVAULT_READY=1` (tối đa 20s); `trap` dọn tiến trình.
2. Đọc `USER/PASS`. Dùng `curl -sS -c jar -b jar`.
3. Các kiểm tra (mỗi cái `assert` bằng hàm `check "mô tả" điều_kiện`, lỗi ⇒ in và `exit 1`):
   - `GET /api/health` = 200; `GET /api/nodes?parent=root` không cookie = 401.
   - login sai = 401; login đúng = 204.
   - tạo thư mục `A`; upload `hello.txt` (text lặp 200KB, 2 khối) và `rand.bin` (`head -c 1048576 /dev/urandom`, 1 khối) và `ảnh.jpg` (`head -c 500000 /dev/urandom`).
   - poll tới `done`; `hello.txt` có `codec":"zlib"`; `rand.bin` có `codec":"raw"`.
   - tải về `cmp` giống file gốc; `Range: bytes=100-199` của `rand.bin` ⇒ 206 + `cmp` đúng đoạn (`dd`/`tail -c`/`head -c`).
   - tag: tạo tag, gắn, search theo tag và theo tên.
   - zip: `curl -o z.zip -d "ids=<id1>,<id2>"` ⇒ `unzip -t z.zip` OK; `unzip -p` nội dung khớp.
   - trash rồi restore; purge; `stats` có `fileCount` đúng.
   - `GET /` trả HTML chứa `ExVault`; `GET /js/../x` = 404.
4. In `ALL PASSED`.
CI đã gọi script này ở job `core` (`docs/07` mục 6).

## Nghiệm thu
- [ ] CI xanh, log CI có `ALL PASSED`. [ ] Script chạy ổn định 3 lần liên tiếp (push 3 lần hoặc `workflow_dispatch`).
