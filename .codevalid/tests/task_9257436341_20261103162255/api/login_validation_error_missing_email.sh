#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"
PASSWORD="Str0ngPass!${SUFFIX: -6}"

# Given
cv_step Given "a login body with a password but no email" $LINENO
BODY=$(jq -nc --arg p "$PASSWORD" '{password:$p}')
cv_http GET /health "" 200

# When
cv_step When "submit the login request without email" $LINENO
cv_http POST /auth/login "$BODY"

# Then
cv_step Then "400 Invalid request with details for the email field" $LINENO
[ "$CV_HTTP_STATUS" = "400" ] || cv_fail "expected HTTP 400 got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO
ERR=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.error // empty')
[ "$ERR" = "Invalid request" ] || cv_fail "expected error 'Invalid request' got '$ERR'" $LINENO
printf '%s' "$CV_HTTP_BODY" | jq -e '.details.email | type == "array" and length > 0' >/dev/null \
  || cv_fail "expected non-empty details.email got $CV_HTTP_BODY" $LINENO
if printf '%s' "$CV_HTTP_BODY" | jq -e '.details | has("password")' >/dev/null; then
  cv_fail "expected no password error for a valid password got $CV_HTTP_BODY" $LINENO
fi
if printf '%s' "$CV_HTTP_BODY" | jq -e 'has("token")' >/dev/null; then
  cv_fail "expected no token got $CV_HTTP_BODY" $LINENO
fi

# Cleanup
cv_step Cleanup "nothing was created" $LINENO
echo "Nothing to clean up"

echo "CODEVALID_TEST_ASSERTION_OK:login_validation_error_missing_email"
