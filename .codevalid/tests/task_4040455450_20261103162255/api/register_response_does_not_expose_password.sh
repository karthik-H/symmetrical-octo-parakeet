#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"
EMAIL="private.${SUFFIX}@example.com"
PASSWORD="SecretPw!${SUFFIX: -6}"

# Given
cv_step Given "a fresh email and a distinctive password" $LINENO
cv_http POST /auth/login "$(jq -nc --arg e "$EMAIL" --arg p "$PASSWORD" '{email:$e,password:$p}')"
[ "$CV_HTTP_STATUS" = "401" ] || cv_fail "expected unused email to be unknown (401) got $CV_HTTP_STATUS" $LINENO

# When
cv_step When "register the account" $LINENO
cv_http POST /auth/register "$(jq -nc --arg e "$EMAIL" --arg p "$PASSWORD" '{email:$e,password:$p}')"

# Then
cv_step Then "response has only token and public user; no password or hash anywhere" $LINENO
[ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected HTTP 201 got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO
TOP=$(printf '%s' "$CV_HTTP_BODY" | jq -c 'keys')
[ "$TOP" = '["token","user"]' ] || cv_fail "expected top-level keys [token,user] got $TOP" $LINENO
UK=$(printf '%s' "$CV_HTTP_BODY" | jq -c '.user | keys')
[ "$UK" = '["email","id","name"]' ] || cv_fail "expected user keys [email,id,name] got $UK" $LINENO
if printf '%s' "$CV_HTTP_BODY" | grep -qF "$PASSWORD"; then
  cv_fail "expected plaintext password absent from response body" $LINENO
fi
if printf '%s' "$CV_HTTP_BODY" | grep -qiE 'password|hash|\$2[aby]\$[0-9]{2}\$'; then
  cv_fail "expected no password/hash field or bcrypt value got: $CV_HTTP_BODY" $LINENO
fi
if grep -qF "$PASSWORD" "$CV_HTTP_HEADERS_FILE"; then
  cv_fail "expected plaintext password absent from response headers" $LINENO
fi
TOKEN=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.token')
PAYLOAD_B64=$(printf '%s' "$TOKEN" | cut -d. -f2 | tr '_-' '/+')
while [ $(( ${#PAYLOAD_B64} % 4 )) -ne 0 ]; do PAYLOAD_B64="${PAYLOAD_B64}="; done
PAYLOAD=$(printf '%s' "$PAYLOAD_B64" | base64 -d 2>/dev/null || true)
echo "token payload: $PAYLOAD"
if printf '%s' "$PAYLOAD" | grep -qiE "password|hash|\\\$2[aby]\\\$" || printf '%s' "$PAYLOAD" | grep -qF "$PASSWORD"; then
  cv_fail "expected token payload without password or hash got: $PAYLOAD" $LINENO
fi
cv_prereq "stored record holds a verifiable hash: login with the password succeeds" $LINENO
cv_http POST /auth/login "$(jq -nc --arg e "$EMAIL" --arg p "$PASSWORD" '{email:$e,password:$p}')"
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected login 200 got $CV_HTTP_STATUS" $LINENO
if printf '%s' "$CV_HTTP_BODY" | grep -qiE 'password|hash|\$2[aby]\$' || printf '%s' "$CV_HTTP_BODY" | grep -qF "$PASSWORD"; then
  cv_fail "expected login response without password or hash got: $CV_HTTP_BODY" $LINENO
fi

# Cleanup
cv_step Cleanup "in-memory store has no delete route; account discarded on restart" $LINENO
echo "No cleanup route; account $EMAIL left in the in-memory store"

echo "CODEVALID_TEST_ASSERTION_OK:register_response_does_not_expose_password"
