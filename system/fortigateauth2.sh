
#!/usr/bin/env bash
set -Eeuo pipefail

# FortiGate configuration
GATEWAY="http://192.168.31.4:1000"
REDIRECT="http://neverssl.com/"

# Firefox User-Agent
USER_AGENT="Mozilla/5.0 (X11; Linux x86_64; rv:132.0) Gecko/20100101 Firefox/132.0"

# Temporary files
TMPDIR=$(mktemp -d)
chmod 700 "$TMPDIR"

COOKIE="$TMPDIR/cookies.txt"
PAGE="$TMPDIR/login.html"
RESPONSE="$TMPDIR/response.html"
HEADERS="$TMPDIR/headers.txt"
LOG="$TMPDIR/curl.log"
STATUS="$TMPDIR/status.txt"

cleanup() {
    unset PASSWORD
    rm -rf "$TMPDIR"
}
trap cleanup EXIT

log() {
    echo "[$(date '+%H:%M:%S')] $*"
}

section() {
    echo
    echo "========================================"
    echo "$1"
    echo "========================================"
}

# Common curl options
CURL_COMMON=(
    --noproxy '*'
    --http1.1
    --connect-timeout 10
    --max-time 25
    -A "$USER_AGENT"
    -c "$COOKIE"
    -b "$COOKIE"
)

section "FORTIGATE CAPTIVE PORTAL LOGIN"

echo "Gateway: $GATEWAY"
echo "User-Agent: Firefox/Linux"

read -rp "Username: " USERNAME
read -rsp "Password: " PASSWORD
echo

# --------------------------------------------------
# 1. Obtain magic token
# --------------------------------------------------

section "1. OBTAINING MAGIC TOKEN"

log "Requesting captive portal redirect..."

if ! curl "${CURL_COMMON[@]}" \
    -fsS "$REDIRECT" \
    -o "$PAGE"; then

    log "ERROR: Could not retrieve captive portal redirect."
    exit 1
fi

MAGIC=$(grep -oP 'fgtauth\?\K[0-9a-fA-F]+' "$PAGE" |
    head -n 1 || true)

if [[ -z "$MAGIC" ]]; then
    log "ERROR: Magic token not found."
    echo "Response:"
    head -c 1500 "$PAGE"
    exit 1
fi

log "Magic token obtained (${#MAGIC} characters)."

PORTAL_URL="${GATEWAY}/fgtauth?${MAGIC}"

# --------------------------------------------------
# 2. Retrieve actual login page
# --------------------------------------------------

section "2. RETRIEVING LOGIN FORM"

log "GET $GATEWAY/fgtauth?[REDACTED]"

if ! curl "${CURL_COMMON[@]}" \
    -fsS "$PORTAL_URL" \
    -o "$PAGE"; then

    log "ERROR: Failed to retrieve login form."
    exit 1
fi

if ! grep -q 'name="username"' "$PAGE" ||
   ! grep -q 'name="password"' "$PAGE"; then

    log "ERROR: Expected login fields not found."
    exit 1
fi

log "Login form successfully retrieved."

# --------------------------------------------------
# 3. Submit authentication
# --------------------------------------------------

section "3. SUBMITTING AUTHENTICATION"

log "POST ${GATEWAY}/"
log "User-Agent: Firefox/Linux"
log "Referer: ${PORTAL_URL}"

: > "$LOG"
: > "$HEADERS"
: > "$RESPONSE"
: > "$STATUS"

if curl "${CURL_COMMON[@]}" \
    -sS \
    -e "$PORTAL_URL" \
    -H "Origin: $GATEWAY" \
    -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
    -H "Accept-Language: tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7" \
    -H "Upgrade-Insecure-Requests: 1" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -D "$HEADERS" \
    -o "$RESPONSE" \
    -w '%{http_code}' \
    -X POST "${GATEWAY}/" \
    --data-urlencode "4Tredir=$REDIRECT" \
    --data-urlencode "magic=$MAGIC" \
    --data-urlencode "username=$USERNAME" \
    --data-urlencode "password=$PASSWORD" \
    > "$STATUS" 2>"$LOG"; then

    CURL_EXIT=0
    HTTP_CODE=$(cat "$STATUS")
else
    CURL_EXIT=$?
    HTTP_CODE=$(cat "$STATUS" 2>/dev/null || echo "000")
fi

unset PASSWORD

log "Curl exit code: $CURL_EXIT"
log "HTTP status: $HTTP_CODE"

echo
echo "--- Response headers ---"
cat "$HEADERS"

echo
echo "--- Curl diagnostics ---"
cat "$LOG"

echo
echo "--- Response body (first 2000 bytes) ---"

if [[ -s "$RESPONSE" ]]; then
    head -c 2000 "$RESPONSE"
    echo
else
    echo "Empty response body."
fi

# --------------------------------------------------
# 4. Interpret response
# --------------------------------------------------

section "4. AUTHENTICATION RESULT"

if [[ "$CURL_EXIT" -ne 0 ]]; then
    log "Transport error during authentication."

    case "$CURL_EXIT" in
        28) log "Connection timeout." ;;
        35) log "TLS handshake error." ;;
        52) log "Server closed connection without HTTP response." ;;
        56) log "Network receive error." ;;
        *)  log "See curl diagnostics above." ;;
    esac
else
    case "$HTTP_CODE" in
        200|302|303)
            log "HTTP response received."
            log "This does not by itself prove authentication succeeded."
            ;;
        401|403)
            log "Authentication or access was rejected."
            ;;
        000)
            log "No HTTP response received."
            ;;
        *)
            log "Unexpected HTTP status: $HTTP_CODE"
            ;;
    esac
fi

# --------------------------------------------------
# 5. Verify connectivity
# --------------------------------------------------

section "5. VERIFYING INTERNET ACCESS"

log "Checking external connectivity..."

if curl "${CURL_COMMON[@]}" \
    -fsS "$REDIRECT" \
    -o "$TMPDIR/check.html"; then

    if grep -q 'window.location=.*192\.168\.31\.4' \
        "$TMPDIR/check.html"; then

        log "Captive portal redirect still present."
        log "Authentication may have failed."
    else
        log "No captive portal redirect detected."
        log "Internet access appears available."
    fi
else
    log "Connectivity check failed."
fi

# --------------------------------------------------
# 6. Summary
# --------------------------------------------------

section "6. SUMMARY"

echo "Gateway: $GATEWAY"
echo "Authentication endpoint: POST /"
echo "HTTP status: $HTTP_CODE"
echo "Curl exit: $CURL_EXIT"

log "Finished."

