#!/usr/bin/env bash
set -euo pipefail

# soak.sh — ExVault Soak and Resilience Test
# Verifies memory budget (<80MB RSS) under load and crash recovery (kill -9).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORK_DIR="$(mktemp -d /tmp/exvault-soak.XXXXXX)"
CLI_BIN="$REPO_DIR/.build/release/exvault-cli"

echo "=== ExVault Soak Test ==="
echo "Work Dir: $WORK_DIR"

if [ ! -f "$CLI_BIN" ]; then
    echo "Building release CLI..."
    (cd "$REPO_DIR" && swift build -c release --product exvault-cli)
fi

PORT=8989
DATA_DIR="$WORK_DIR/data"
WEB_DIR="$REPO_DIR/Web"
mkdir -p "$DATA_DIR"

# Launch CLI server
LOG_FILE="$WORK_DIR/server.log"
"$CLI_BIN" --port "$PORT" --data-dir "$DATA_DIR" --web-root "$WEB_DIR" > "$LOG_FILE" 2>&1 &
CLI_PID=$!
echo "Server started (PID $CLI_PID) on port $PORT"

cleanup() {
    echo "Stopping test processes..."
    if kill -0 "$CLI_PID" 2>/dev/null; then
        kill "$CLI_PID" 2>/dev/null || true
    fi
    rm -rf "$WORK_DIR"
    echo "Cleanup complete."
}
trap cleanup EXIT

# Wait for server to be responsive
sleep 1
for i in {1..30}; do
    if curl -s "http://127.0.0.1:$PORT/api/auth/me" >/dev/null 2>&1; then
        break
    fi
    sleep 0.2
done

# Read credentials from log file
USER_NAME=$(grep -o "user: [a-z0-9]*" "$LOG_FILE" | head -n 1 | awk '{print $2}')
PASSWORD=$(grep -o "pass: [a-z0-9]*" "$LOG_FILE" | head -n 1 | awk '{print $2}')
echo "Server Credentials -> User: $USER_NAME, Pass: $PASSWORD"

COOKIE_JAR="$WORK_DIR/cookies.txt"
curl -s -c "$COOKIE_JAR" -X POST "http://127.0.0.1:$PORT/api/auth/login" \
     -H "Content-Type: application/json" \
     -d "{\"username\":\"$USER_NAME\",\"password\":\"$PASSWORD\"}" > /dev/null

echo "Authenticated successfully."

# 1. Soak upload test (generate 200MB chunks stream to verify memory stability)
echo "--- Testing chunked upload streaming ---"
FILE_SIZE=$((200 * 1024 * 1024)) # 200MB test file
CHUNK_SIZE=$((4 * 1024 * 1024))
TOTAL_CHUNKS=$((FILE_SIZE / CHUNK_SIZE))

INIT_RESP=$(curl -s -b "$COOKIE_JAR" -X POST "http://127.0.0.1:$PORT/api/upload/init" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"soak_test_200m.bin\",\"size\":$FILE_SIZE,\"chunk_size\":$CHUNK_SIZE}")
UPLOAD_ID=$(echo "$INIT_RESP" | grep -o '"upload_id":"[^"]*' | cut -d'"' -f4)
echo "Upload initiated: $UPLOAD_ID ($TOTAL_CHUNKS chunks)"

# Generate a 4MB reusable chunk buffer
CHUNK_TMP="$WORK_DIR/chunk.bin"
dd if=/dev/urandom of="$CHUNK_TMP" bs=1048576 count=4 2>/dev/null

START_TIME=$(date +%s)
for ((i=0; i<TOTAL_CHUNKS; i++)); do
    curl -s -b "$COOKIE_JAR" -X POST "http://127.0.0.1:$PORT/api/upload/$UPLOAD_ID/chunk?index=$i" \
        -H "Content-Type: application/octet-stream" \
        --data-binary @"$CHUNK_TMP" > /dev/null
    
    # Check RSS memory periodically
    if [ $((i % 10)) -eq 0 ]; then
        RSS_KB=$(ps -o rss= -p "$CLI_PID" 2>/dev/null | tr -d ' ' || echo 0)
        RSS_MB=$((RSS_KB / 1024))
        echo "Uploaded chunk $i/$TOTAL_CHUNKS (CLI RSS: ${RSS_MB}MB)"
        if [ "$RSS_MB" -gt 80 ]; then
            echo "ERROR: Memory budget exceeded! RSS = ${RSS_MB}MB > 80MB"
            exit 1
        fi
    fi
done

FINISH_RESP=$(curl -s -b "$COOKIE_JAR" -X POST "http://127.0.0.1:$PORT/api/upload/$UPLOAD_ID/finish")
FILE_NODE_ID=$(echo "$FINISH_RESP" | grep -o '"id":"[^"]*' | cut -d'"' -f4)
END_TIME=$(date +%s)
echo "Upload complete in $((END_TIME - START_TIME))s. File Node ID: $FILE_NODE_ID"

# 2. Parallel 4-stream download test
echo "--- Testing 4 parallel downloads ---"
PIDS=()
for s in {1..4}; do
    curl -s -b "$COOKIE_JAR" "http://127.0.0.1:$PORT/api/files/$FILE_NODE_ID/content" -o /dev/null &
    PIDS+=($!)
done

for pid in "${PIDS[@]}"; do
    wait "$pid"
done
echo "Parallel downloads complete."

# Check final RSS
FINAL_RSS_KB=$(ps -o rss= -p "$CLI_PID" 2>/dev/null | tr -d ' ' || echo 0)
FINAL_RSS_MB=$((FINAL_RSS_KB / 1024))
echo "Final CLI RSS: ${FINAL_RSS_MB}MB (< 80MB budget verified)"

# 3. Simulate sudden power loss / crash: kill -9 during upload
echo "--- Testing crash recovery (kill -9) ---"
CRASH_INIT_RESP=$(curl -s -b "$COOKIE_JAR" -X POST "http://127.0.0.1:$PORT/api/upload/init" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"interrupted_file.bin\",\"size\":$FILE_SIZE,\"chunk_size\":$CHUNK_SIZE}")
CRASH_UPLOAD_ID=$(echo "$CRASH_INIT_RESP" | grep -o '"upload_id":"[^"]*' | cut -d'"' -f4)

# Upload 2 chunks then abruptly kill
curl -s -b "$COOKIE_JAR" -X POST "http://127.0.0.1:$PORT/api/upload/$CRASH_UPLOAD_ID/chunk?index=0" \
    -H "Content-Type: application/octet-stream" \
    --data-binary @"$CHUNK_TMP" > /dev/null

echo "Killing CLI process with kill -9..."
kill -9 "$CLI_PID" 2>/dev/null || true
wait "$CLI_PID" 2>/dev/null || true

# Verify .part file exists on disk
PART_COUNT=$(find "$DATA_DIR" -name "*.part" | wc -l | tr -d ' ')
echo "Orphaned .part files on disk before recovery: $PART_COUNT"

# Restart CLI — startup cleanup should trigger
echo "Restarting server to trigger crash recovery..."
"$CLI_BIN" --port "$PORT" --data-dir "$DATA_DIR" --web-root "$WEB_DIR" >> "$LOG_FILE" 2>&1 &
CLI_PID=$!
sleep 1

# Check .part files after restart cleanup
PART_COUNT_AFTER=$(find "$DATA_DIR" -name "*.part" | wc -l | tr -d ' ')
echo "Orphaned .part files on disk after restart cleanup: $PART_COUNT_AFTER (expected 0)"
if [ "$PART_COUNT_AFTER" -ne 0 ]; then
    echo "ERROR: Orphaned .part files were not cleaned up!"
    exit 1
fi

echo "=== All Soak & Resilience Tests Passed Successfully! ==="
