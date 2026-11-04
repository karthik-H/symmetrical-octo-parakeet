#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"
EMAIL="dup.${SUFFIX}@example.com"
PASSWORD="FirstPass!${SUFFIX: -4}"
PASSWORD2="SecondPass!${SUFFIX: -4}"

# Given
cv_step Given "an account already registered with the email" $LINENO
cv_http POST /auth/register "$(jq -nc --arg e "$EMAIL" --arg p "$PASSWORD" '{email:$e,password:$p,name:"First Owner"}')"
[ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected first registration 201 got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO
FIRST_ID=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.user.id // empty')
[ -n "$FIRST_ID" ] || cv_fail "expected first user id got none" $LINENO

# When
cv_step When "register again with the same email (different case) and another password" $LINENO
UPPER_EMAIL=$(printf '%s' "$EMAIL" | tr '[:lower:]' '[:upper:]')
cv_http POST /auth/register "$(jq -nc --arg e "$UPPER_EMAIL" --arg p "$PASSWORD2" '{email:$e,password:$p,name:"Intruder"}')"

# Then
cv_step Then "409 email already registered and the original account is unchanged" $LINENO
[ "$CV_HTTP_STATUS" = "409" ] || cv_fail "expected HTTP 409 got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO
ERR=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.error // empty')
printf '%s' "$ERR" | grep -qi 'already registered' || cv_fail "expected error indicating email already registered got '$ERR'" $LINENO
if printf '%s' "$CV_HTTP_BODY" | jq -e 'has("token") or has("user")' >/dev/null; then
  cv_fail "expected no token/user in duplicate response got: $CV_HTTP_BODY" $LINENO
fi
cv_http POST /auth/login "$(jq -nc --arg e "$EMAIL" --arg p "$PASSWORD2" '{email:$e,password:$p}')"
[ "$CV_HTTP_STATUS" = "401" ] || cv_fail "expected second password not to work (401) got $CV_HTTP_STATUS" $LINENO
cv_http POST /auth/login "$(jq -nc --arg e "$EMAIL" --arg p "$PASSWORD" '{email:$e,password:$p}')"
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected original password to still work (200) got $CV_HTTP_STATUS" $LINENO
LID=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.user.id // empty')
[ "$LID" = "$FIRST_ID" ] || cv_fail "expected original user id $FIRST_ID got $LID" $LINENO
LNAME=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.user.name // empty')
[ "$LNAME" = "First Owner" ] || cv_fail "expected original name 'First Owner' got '$LNAME'" $LINENO

# Cleanup
cv_step Cleanup "in-memory store has no delete route; account discarded on restart" $LINENO
echo "No cleanup route; account $EMAIL left in the in-memory store"

echo "CODEVALID_TEST_ASSERTION_OK:register_duplicate_email"
