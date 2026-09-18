#!/usr/bin/env bash

#The script:requests an HTTP-only site,
#finds the FortiGate authentication URL,
#extracts the current token,
#securely prompts for credentials,
#submits the login request,
#checks the HTTP status,
#verifies Internet connectivity.

#Usage
#make executable
#chmod 700 ~/fortigateauth.sh
#Then run:
#~/fortigateauth.sh

set -u

CHECK_URL="http://neverssl.com/"
VERIFY_URL="https://google.com/"
FIREWALL="http://192.168.31.4:1000"

echo "Checking network authentication state..."

PAGE=$(curl -fsS "$CHECK_URL" 2>/dev/null || true)

if curl -fsS --head "$VERIFY_URL" >/dev/null 2>&1; then
    echo "Internet access is already available."
    exit 0
fi

MAGIC=$(printf '%s' "$PAGE" \
    | grep -oE 'fgtauth\?[A-Za-z0-9]+' \
    | head -n1 \
    | cut -d'?' -f2)

if [[ -z "${MAGIC:-}" ]]; then
    echo "Could not detect a FortiGate authentication token."
    echo "Check the captive portal response manually with:"
    echo "  curl -v $CHECK_URL"
    exit 1
fi

echo "FortiGate captive portal detected."
echo "Session token: $MAGIC"

read -rp "Username: " USERNAME
read -srp "Password: " PASSWORD
echo

HTTP_CODE=$(
    curl -sS \
        -o /tmp/fortigate-login-response.html \
        -w "%{http_code}" \
        --data-urlencode "username=$USERNAME" \
        --data-urlencode "password=$PASSWORD" \
        --data-urlencode "magic=$MAGIC" \
        --data-urlencode "4Tredir=$CHECK_URL" \
        "$FIREWALL/"
)

unset PASSWORD

echo "Firewall response: HTTP $HTTP_CODE"

if [[ "$HTTP_CODE" == "303" || "$HTTP_CODE" == "302" ]]; then
    echo "Authentication request accepted."
else
    echo "Unexpected firewall response."
    echo "Response saved to:"
    echo "  /tmp/fortigate-login-response.html"
fi

echo "Verifying Internet access..."

if curl -fsS --head "$VERIFY_URL" >/dev/null 2>&1; then
    echo "Internet access is working."
    exit 0
else
    echo "Authentication may have failed or Internet access is still blocked."
    exit 1
fi
