#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"
EMAIL="login.happy.${SUFFIX}@example.com"
PASSWORD="Str0ngPass!${SUFFIX: -6}"
NAME="Login Happy ${SUFFIX: -6}"

# Given
cv_step Given "a registered customer account" $LINENO
cv_http POST /auth/register "$(jq -nc --arg e "$EMAIL" --arg p "$PASSWORD" --arg n "$NAME" '{email:$e,password:$p,name:$n}')"
[ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected registration 201 got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO
REG_ID=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.user.id // empty')
[ -n "$REG_ID" ] || cv_fail "expected registered user id got none" $LINENO

# When
cv_step When "sign in with the registered email and correct password" $LINENO
cv_http POST /auth/login "$(jq -nc --arg e "$EMAIL" --arg p "$PASSWORD" '{email:$e,password:$p}')"

# Then
cv_step Then "200 with a JWT token and the public profile without password" $LINENO
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected HTTP 200 got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO
TOKEN=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.token // empty')
[ -n "$TOKEN" ] || cv_fail "expected non-empty token got none" $LINENO
[ "$(printf '%s' "$TOKEN" | awk -F. '{print NF}')" = "3" ] || cv_fail "expected JWT-shaped token got '$TOKEN'" $LINENO
UID_=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.user.id // empty')
[ "$UID_" = "$REG_ID" ] || cv_fail "expected user.id $REG_ID got '$UID_'" $LINENO
UEMAIL=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.user.email // empty')
[ "$UEMAIL" = "$EMAIL" ] || cv_fail "expected user.email $EMAIL got '$UEMAIL'" $LINENO
UNAME=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.user.name // empty')
[ "$UNAME" = "$NAME" ] || cv_fail "expected user.name '$NAME' got '$UNAME'" $LINENO
if printf '%s' "$CV_HTTP_BODY" | jq -e '.user | has("password") or has("passwordHash")' >/dev/null; then
  cv_fail "expected no password/passwordHash in user got $CV_HTTP_BODY" $LINENO
fi
if printf '%s' "$CV_HTTP_BODY" | grep -qiE 'password|\$2[aby]\$'; then
  cv_fail "expected no password or bcrypt hash in response got $CV_HTTP_BODY" $LINENO
fi
if printf '%s' "$CV_HTTP_BODY" | grep -qF "$PASSWORD"; then
  cv_fail "expected plaintext password absent from response" $LINENO
fi
cv_prereq "token authenticates a catalog change (signed-in only)" $LINENO
cv_http POST /products '{"name":"Login token check","description":"x","price":1}' -H "Authorization: Bearer $TOKEN"
[ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected login token accepted for POST /products (201) got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO

# Cleanup
cv_step Cleanup "in-memory store has no delete route; data discarded on restart" $LINENO
echo "No delete route; account $EMAIL left in the in-memory store"

echo "CODEVALID_TEST_ASSERTION_OK:login_happy_valid_credentials"
