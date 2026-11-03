#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"
EMAIL="nopw.${SUFFIX}@example.com"

# Given
cv_step Given "a login body with an email but no password" $LINENO
BODY=$(jq -nc --arg e "$EMAIL" '{email:$e}')
cv_http GET /health "" 200

# When
cv_step When "submit the login request without password" $LINENO
cv_http POST /auth/login "$BODY"

# Then
cv_step Then "400 Invalid request with details for the password field" $LINENO
[ "$CV_HTTP_STATUS" = "400" ] || cv_fail "expected HTTP 400 got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO
ERR=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.error // empty')
[ "$ERR" = "Invalid request" ] || cv_fail "expected error 'Invalid request' got '$ERR'" $LINENO
printf '%s' "$CV_HTTP_BODY" | jq -e '.details.password | type == "array" and length > 0' >/dev/null \
  || cv_fail "expected non-empty details.password got $CV_HTTP_BODY" $LINENO
if printf '%s' "$CV_HTTP_BODY" | jq -e '.details | has("email")' >/dev/null; then
  cv_fail "expected no email error for a valid email got $CV_HTTP_BODY" $LINENO
fi
if printf '%s' "$CV_HTTP_BODY" | jq -e 'has("token")' >/dev/null; then
  cv_fail "expected no token got $CV_HTTP_BODY" $LINENO
fi

# Cleanup
cv_step Cleanup "nothing was created" $LINENO
echo "Nothing to clean up"

echo "CODEVALID_TEST_ASSERTION_OK:login_validation_error_missing_password"
