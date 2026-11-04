#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"
EMAIL="ignorename.${SUFFIX}@example.com"
PASSWORD="Str0ngPass!${SUFFIX: -6}"
NAME="Original Name ${SUFFIX: -6}"
# An extra name that would fail the register schema (empty after trim), to prove login ignores it
EXTRA_NAME="   "

# Given
cv_step Given "a registered account with a known display name" $LINENO
cv_http POST /auth/register "$(jq -nc --arg e "$EMAIL" --arg p "$PASSWORD" --arg n "$NAME" '{email:$e,password:$p,name:$n}')"
[ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected registration 201 got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO
REG_ID=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.user.id // empty')
[ -n "$REG_ID" ] || cv_fail "expected registered user id got none" $LINENO

# When
cv_step When "sign in with valid email and password plus an extra name field" $LINENO
cv_http POST /auth/login "$(jq -nc --arg e "$EMAIL" --arg p "$PASSWORD" --arg n "$EXTRA_NAME" '{email:$e,password:$p,name:$n}')"

# Then
cv_step Then "login succeeds normally and the name field changes nothing" $LINENO
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected HTTP 200 got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO
TOKEN=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.token // empty')
[ -n "$TOKEN" ] || cv_fail "expected non-empty token got none" $LINENO
UID_=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.user.id // empty')
[ "$UID_" = "$REG_ID" ] || cv_fail "expected user.id $REG_ID got '$UID_'" $LINENO
UNAME=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.user.name // empty')
[ "$UNAME" = "$NAME" ] || cv_fail "expected stored name '$NAME' unchanged got '$UNAME'" $LINENO
cv_prereq "a different arbitrary name also logs in to the same account" $LINENO
cv_http POST /auth/login "$(jq -nc --arg e "$EMAIL" --arg p "$PASSWORD" '{email:$e,password:$p,name:"Somebody Else"}')"
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected HTTP 200 with a different name got $CV_HTTP_STATUS" $LINENO
UNAME2=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.user.name // empty')
[ "$UNAME2" = "$NAME" ] || cv_fail "expected stored name '$NAME' unchanged got '$UNAME2'" $LINENO
cv_prereq "a name field does not rescue a wrong password" $LINENO
cv_http POST /auth/login "$(jq -nc --arg e "$EMAIL" --arg p "Wrong${PASSWORD}" --arg n "$NAME" '{email:$e,password:$p,name:$n}')"
[ "$CV_HTTP_STATUS" = "401" ] || cv_fail "expected HTTP 401 for wrong password with name got $CV_HTTP_STATUS" $LINENO

# Cleanup
cv_step Cleanup "in-memory store has no delete route; data discarded on restart" $LINENO
echo "No delete route; account $EMAIL left in the in-memory store"

echo "CODEVALID_TEST_ASSERTION_OK:login_ignores_name_field"
