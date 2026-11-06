#!/usr/bin/env bash
set -euo pipefail

echo "=== ExVault CLI Integration Test Suite ==="

TMP=$(mktemp -d)
JAR="$TMP/cookie.jar"
mkdir -p "$TMP/data"

CLI_PID=""
cleanup() {
  local exit_code=$?
  if [ -n "$CLI_PID" ]; then
    echo "Stopping exvault-cli (PID: $CLI_PID)..."
    kill -TERM "$CLI_PID" 2>/dev/null || true
    wait "$CLI_PID" 2>/dev/null || true
  fi
  rm -rf "$TMP"
  exit $exit_code
}
trap cleanup EXIT INT TERM

check() {
  local desc="$1"
  local cond="$2"
  if eval "$cond"; then
    echo "✓ $desc"
  else
    echo "✗ FAILED: $desc"
    echo "Condition: $cond"
    if [ -f "$TMP/out.log" ]; then
      echo "--- Server output log ---"
      tail -n 100 "$TMP/out.log"
    fi
    exit 1
  fi
}

# 1. Start exvault-cli on port 18080
echo "Starting exvault-cli..."
.build/release/exvault-cli --data "$TMP/data" --web Web --port 18080 > "$TMP/out.log" 2>&1 &
CLI_PID=$!

echo "Waiting for EXVAULT_READY=1..."
READY=0
for _ in $(seq 1 40); do
  if grep -q "EXVAULT_READY=1" "$TMP/out.log" 2>/dev/null; then
    READY=1
    break
  fi
  sleep 0.5
done

if [ "$READY" -ne 1 ]; then
  echo "Timed out waiting for server to become ready."
  cat "$TMP/out.log"
  exit 1
fi

EXVAULT_URL=$(grep "EXVAULT_URL=" "$TMP/out.log" | cut -d= -f2-)
EXVAULT_USER=$(grep "EXVAULT_USER=" "$TMP/out.log" | cut -d= -f2-)
EXVAULT_PASS=$(grep "EXVAULT_PASS=" "$TMP/out.log" | cut -d= -f2-)

echo "Server running at $EXVAULT_URL with user: $EXVAULT_USER"

# 2. Health and unauthorized check
HEALTH_STATUS=$(curl -sS -o /dev/null -w "%{http_code}" "$EXVAULT_URL/api/health")
check "GET /api/health returns 200" '[ "$HEALTH_STATUS" = "200" ]'

UNAUTH_STATUS=$(curl -sS -o /dev/null -w "%{http_code}" "$EXVAULT_URL/api/nodes?parent=root")
check "GET /api/nodes without cookie returns 401" '[ "$UNAUTH_STATUS" = "401" ]'

# 3. Authentication checks
BAD_LOGIN_STATUS=$(curl -sS -o /dev/null -w "%{http_code}" \
  -H "Content-Type: application/json" \
  -d '{"username":"baduser","password":"wrongpassword"}' \
  "$EXVAULT_URL/api/login")
check "Bad login returns 401" '[ "$BAD_LOGIN_STATUS" = "401" ]'

LOGIN_STATUS=$(curl -sS -c "$JAR" -o /dev/null -w "%{http_code}" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$EXVAULT_USER\",\"password\":\"$EXVAULT_PASS\"}" \
  "$EXVAULT_URL/api/login")
check "Good login returns 204" '[ "$LOGIN_STATUS" = "204" ]'

# 4. Create folder A
FOLDER_RESP=$(curl -sS -b "$JAR" \
  -H "Content-Type: application/json" \
  -d '{"name":"A"}' \
  "$EXVAULT_URL/api/folders")
FOLDER_A_ID=$(echo "$FOLDER_RESP" | python3 -c "import sys, json; print(json.load(sys.stdin)['id'])")
check "Created folder A" '[ -n "$FOLDER_A_ID" ]'

# 5. Prepare test files
# hello.txt: repetitive compressible text of ~200KB
python3 -c 'print("This is a highly compressible log message line in hello.txt. " * 3500)' > "$TMP/hello.txt"
HELLO_SIZE=$(wc -c < "$TMP/hello.txt" | tr -d ' ')

# rand.bin: exactly 1MB (1048576 bytes) random binary
head -c 1048576 /dev/urandom > "$TMP/rand.bin"
RAND_SIZE=1048576

# ảnh.jpg: 500000 bytes pseudo image
head -c 500000 /dev/urandom > "$TMP/anh.jpg"
ANH_SIZE=500000

# 6. Upload hello.txt in 2 chunks of ~100KB
INIT_HELLO=$(curl -sS -b "$JAR" \
  -H "Content-Type: application/json" \
  -d "{\"parentId\":\"$FOLDER_A_ID\",\"name\":\"hello.txt\",\"size\":$HELLO_SIZE,\"compress\":\"auto\"}" \
  "$EXVAULT_URL/api/upload")
UPLOAD_HELLO_ID=$(echo "$INIT_HELLO" | python3 -c "import sys, json; print(json.load(sys.stdin)['uploadId'])")

CHUNK_SIZE=100000
head -c $CHUNK_SIZE "$TMP/hello.txt" | curl -sS -b "$JAR" -X PUT \
  -H "Content-Type: application/octet-stream" \
  --data-binary @- \
  "$EXVAULT_URL/api/upload/$UPLOAD_HELLO_ID?offset=0" > /dev/null

tail -c +100001 "$TMP/hello.txt" | curl -sS -b "$JAR" -X PUT \
  -H "Content-Type: application/octet-stream" \
  --data-binary @- \
  "$EXVAULT_URL/api/upload/$UPLOAD_HELLO_ID?offset=$CHUNK_SIZE" > /dev/null

curl -sS -b "$JAR" -X POST "$EXVAULT_URL/api/upload/$UPLOAD_HELLO_ID/finish" > /dev/null

# 7. Upload rand.bin in 1 chunk (1MB)
INIT_RAND=$(curl -sS -b "$JAR" \
  -H "Content-Type: application/json" \
  -d "{\"parentId\":\"$FOLDER_A_ID\",\"name\":\"rand.bin\",\"size\":$RAND_SIZE,\"compress\":\"off\"}" \
  "$EXVAULT_URL/api/upload")
UPLOAD_RAND_ID=$(echo "$INIT_RAND" | python3 -c "import sys, json; print(json.load(sys.stdin)['uploadId'])")

curl -sS -b "$JAR" -X PUT \
  -H "Content-Type: application/octet-stream" \
  --data-binary @"$TMP/rand.bin" \
  "$EXVAULT_URL/api/upload/$UPLOAD_RAND_ID?offset=0" > /dev/null

curl -sS -b "$JAR" -X POST "$EXVAULT_URL/api/upload/$UPLOAD_RAND_ID/finish" > /dev/null

# 8. Upload ảnh.jpg in 1 chunk
INIT_ANH=$(curl -sS -b "$JAR" \
  -H "Content-Type: application/json" \
  -d "{\"parentId\":\"$FOLDER_A_ID\",\"name\":\"ảnh.jpg\",\"size\":$ANH_SIZE,\"compress\":\"auto\"}" \
  "$EXVAULT_URL/api/upload")
UPLOAD_ANH_ID=$(echo "$INIT_ANH" | python3 -c "import sys, json; print(json.load(sys.stdin)['uploadId'])")

curl -sS -b "$JAR" -X PUT \
  -H "Content-Type: application/octet-stream" \
  --data-binary @"$TMP/anh.jpg" \
  "$EXVAULT_URL/api/upload/$UPLOAD_ANH_ID?offset=0" > /dev/null

curl -sS -b "$JAR" -X POST "$EXVAULT_URL/api/upload/$UPLOAD_ANH_ID/finish" > /dev/null

# 9. Wait for upload processing completion
wait_for_done() {
  local uid="$1"
  for _ in $(seq 1 50); do
    local st
    st=$(curl -sS -b "$JAR" "$EXVAULT_URL/api/upload/$uid" | python3 -c "import sys, json; print(json.load(sys.stdin).get('state',''))")
    if [ "$st" = "done" ]; then
      return 0
    elif [ "$st" = "error" ]; then
      echo "Upload $uid failed!"
      return 1
    fi
    sleep 0.1
  done
  echo "Upload $uid timed out waiting for done"
  return 1
}

wait_for_done "$UPLOAD_HELLO_ID"
wait_for_done "$UPLOAD_RAND_ID"
wait_for_done "$UPLOAD_ANH_ID"

# 10. Verify codecs
HELLO_NODE=$(curl -sS -b "$JAR" "$EXVAULT_URL/api/upload/$UPLOAD_HELLO_ID" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['node']['id'], d['node']['codec'])")
NODE_HELLO_ID=$(echo "$HELLO_NODE" | cut -d' ' -f1)
CODEC_HELLO=$(echo "$HELLO_NODE" | cut -d' ' -f2)
check "hello.txt encoded as zlib" '[ "$CODEC_HELLO" = "zlib" ]'

RAND_NODE=$(curl -sS -b "$JAR" "$EXVAULT_URL/api/upload/$UPLOAD_RAND_ID" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['node']['id'], d['node']['codec'])")
NODE_RAND_ID=$(echo "$RAND_NODE" | cut -d' ' -f1)
CODEC_RAND=$(echo "$RAND_NODE" | cut -d' ' -f2)
check "rand.bin stored as raw" '[ "$CODEC_RAND" = "raw" ]'

ANH_NODE=$(curl -sS -b "$JAR" "$EXVAULT_URL/api/upload/$UPLOAD_ANH_ID" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['node']['id'])")
NODE_ANH_ID="$ANH_NODE"

# 11. Download and verify content identity
curl -sS -b "$JAR" "$EXVAULT_URL/api/files/$NODE_HELLO_ID/content" -o "$TMP/downloaded_hello.txt"
check "Downloaded hello.txt matches original" 'cmp "$TMP/hello.txt" "$TMP/downloaded_hello.txt"'

curl -sS -b "$JAR" "$EXVAULT_URL/api/files/$NODE_RAND_ID/content" -o "$TMP/downloaded_rand.bin"
check "Downloaded rand.bin matches original" 'cmp "$TMP/rand.bin" "$TMP/downloaded_rand.bin"'

# 12. Range request for rand.bin (bytes 100-199)
RANGE_STATUS=$(curl -sS -b "$JAR" -H "Range: bytes=100-199" -o "$TMP/range_100_199.bin" -w "%{http_code}" "$EXVAULT_URL/api/files/$NODE_RAND_ID/content")
check "Range request returns 206" '[ "$RANGE_STATUS" = "206" ]'

dd if="$TMP/rand.bin" of="$TMP/expected_range.bin" bs=1 skip=100 count=100 2>/dev/null
check "Range content matches slice" 'cmp "$TMP/range_100_199.bin" "$TMP/expected_range.bin"'

# 13. Tags CRUD, Apply, and Search
TAG_RESP=$(curl -sS -b "$JAR" \
  -H "Content-Type: application/json" \
  -d '{"name":"Important","color":"#ff0000"}' \
  "$EXVAULT_URL/api/tags")
TAG_ID=$(echo "$TAG_RESP" | python3 -c "import sys, json; print(json.load(sys.stdin)['id'])")
check "Created tag 'Important'" '[ -n "$TAG_ID" ]'

curl -sS -b "$JAR" \
  -H "Content-Type: application/json" \
  -d "{\"ids\":[\"$NODE_HELLO_ID\"],\"add\":[$TAG_ID],\"remove\":[]}" \
  "$EXVAULT_URL/api/nodes/tag" > /dev/null

SEARCH_TAG_COUNT=$(curl -sS -b "$JAR" "$EXVAULT_URL/api/search?tag=$TAG_ID" | python3 -c "import sys, json; print(len(json.load(sys.stdin)['items']))")
check "Search by tag returns 1 item" '[ "$SEARCH_TAG_COUNT" = "1" ]'

SEARCH_NAME_COUNT=$(curl -sS -b "$JAR" "$EXVAULT_URL/api/search?q=hello" | python3 -c "import sys, json; print(len(json.load(sys.stdin)['items']))")
check "Search by query returns 1 item" '[ "$SEARCH_NAME_COUNT" = "1" ]'

# 14. Zip download and inspection
curl -sS -b "$JAR" -o "$TMP/archive.zip" -d "ids=$NODE_HELLO_ID,$NODE_RAND_ID" "$EXVAULT_URL/api/zip"
check "ZIP file integrity (unzip -t)" 'unzip -t "$TMP/archive.zip"'

unzip -p "$TMP/archive.zip" "hello.txt" > "$TMP/unzipped_hello.txt"
check "Unzipped hello.txt matches original" 'cmp "$TMP/hello.txt" "$TMP/unzipped_hello.txt"'

# 15. Trash, restore, purge, stats
curl -sS -b "$JAR" \
  -H "Content-Type: application/json" \
  -d "{\"ids\":[\"$NODE_HELLO_ID\"]}" \
  "$EXVAULT_URL/api/nodes/trash" > /dev/null

TRASH_COUNT_1=$(curl -sS -b "$JAR" "$EXVAULT_URL/api/trash" | python3 -c "import sys, json; print(len(json.load(sys.stdin)['items']))")
check "Trash contains 1 item" '[ "$TRASH_COUNT_1" = "1" ]'

curl -sS -b "$JAR" \
  -H "Content-Type: application/json" \
  -d "{\"ids\":[\"$NODE_HELLO_ID\"]}" \
  "$EXVAULT_URL/api/nodes/restore" > /dev/null

TRASH_COUNT_2=$(curl -sS -b "$JAR" "$EXVAULT_URL/api/trash" | python3 -c "import sys, json; print(len(json.load(sys.stdin)['items']))")
check "Trash empty after restore" '[ "$TRASH_COUNT_2" = "0" ]'

curl -sS -b "$JAR" \
  -H "Content-Type: application/json" \
  -d "{\"ids\":[\"$NODE_HELLO_ID\"]}" \
  "$EXVAULT_URL/api/nodes/trash" > /dev/null

curl -sS -b "$JAR" \
  -H "Content-Type: application/json" \
  -d "{\"ids\":[\"$NODE_HELLO_ID\"]}" \
  "$EXVAULT_URL/api/nodes/purge" > /dev/null

STATS_FILES=$(curl -sS -b "$JAR" "$EXVAULT_URL/api/stats" | python3 -c "import sys, json; print(json.load(sys.stdin)['fileCount'])")
check "Stats fileCount is 2 after purge" '[ "$STATS_FILES" = "2" ]'

# 16. Static files and path traversal protection
INDEX_CONTENT=$(curl -sS "$EXVAULT_URL/")
check "GET / returns index.html containing ExVault" 'echo "$INDEX_CONTENT" | grep -q "ExVault"'

APP_JS_CODE=$(curl -sS -o /dev/null -w "%{http_code}" "$EXVAULT_URL/js/app.js")
check "GET /js/app.js returns 200" '[ "$APP_JS_CODE" = "200" ]'

TRAVERSAL_CODE=$(curl -sS -o /dev/null -w "%{http_code}" "$EXVAULT_URL/js/../x")
check "Path traversal /js/../x returns 404" '[ "$TRAVERSAL_CODE" = "404" ]'

echo "ALL PASSED"
