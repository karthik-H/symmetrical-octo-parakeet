#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"
EMAIL="wrongpw.${SUFFIX}@example.com"
PASSWORD="Str0ngPass!${SUFFIX: -6}"
WRONG="WrongPass!${SUFFIX: -6}"
UNKNOWN="unknown.${SUFFIX}@example.com"

# Given
cv_step Given "a registered account and the response for an unknown account" $LINENO
cv_http POST /auth/register "$(jq -nc --arg e "$EMAIL" --arg p "$PASSWORD" '{email:$e,password:$p}')"
[ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected registration 201 got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO
cv_prereq "baseline login for an unknown email" $LINENO
cv_http POST /auth/login "$(jq -nc --arg e "$UNKNOWN" --arg p "$WRONG" '{email:$e,password:$p}')"
UNKNOWN_STATUS="$CV_HTTP_STATUS"
UNKNOWN_BODY=$(printf '%s' "$CV_HTTP_BODY" | jq -cS '.')

# When
cv_step When "sign in with the registered email and a wrong password" $LINENO
cv_http POST /auth/login "$(jq -nc --arg e "$EMAIL" --arg p "$WRONG" '{email:$e,password:$p}')"

# Then
cv_step Then "401 with the same generic message as for an unknown account" $LINENO
[ "$CV_HTTP_STATUS" = "401" ] || cv_fail "expected HTTP 401 got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO
ERR=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.error // empty')
[ "$ERR" = "Invalid email or password" ] || cv_fail "expected error 'Invalid email or password' got '$ERR'" $LINENO
if printf '%s' "$CV_HTTP_BODY" | jq -e 'has("token") or has("user")' >/dev/null; then
  cv_fail "expected no token or user on failure got $CV_HTTP_BODY" $LINENO
fi
WRONG_BODY=$(printf '%s' "$CV_HTTP_BODY" | jq -cS '.')
[ "$UNKNOWN_STATUS" = "$CV_HTTP_STATUS" ] || cv_fail "expected same status as unknown email ($UNKNOWN_STATUS) got $CV_HTTP_STATUS" $LINENO
[ "$UNKNOWN_BODY" = "$WRONG_BODY" ] || cv_fail "expected identical body to unknown-email response $UNKNOWN_BODY got $WRONG_BODY" $LINENO

# Cleanup
cv_step Cleanup "in-memory store has no delete route; data discarded on restart" $LINENO
echo "No delete route; account $EMAIL left in the in-memory store"

echo "CODEVALID_TEST_ASSERTION_OK:login_wrong_password"
