#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"
EMAIL="nobody.${SUFFIX}@example.com"
PASSWORD="AnyPass!${SUFFIX: -6}"

# Given
cv_step Given "an email address that has no account" $LINENO
cv_prereq "registering is not done for $EMAIL; the service is reachable" $LINENO
cv_http GET /health "" 200

# When
cv_step When "sign in with the unregistered email and some password" $LINENO
cv_http POST /auth/login "$(jq -nc --arg e "$EMAIL" --arg p "$PASSWORD" '{email:$e,password:$p}')"

# Then
cv_step Then "401 with only the generic invalid credentials message" $LINENO
[ "$CV_HTTP_STATUS" = "401" ] || cv_fail "expected HTTP 401 got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO
ERR=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.error // empty')
[ "$ERR" = "Invalid email or password" ] || cv_fail "expected error 'Invalid email or password' got '$ERR'" $LINENO
KEYS=$(printf '%s' "$CV_HTTP_BODY" | jq -c 'keys')
[ "$KEYS" = '["error"]' ] || cv_fail "expected only an error field got keys $KEYS" $LINENO
if printf '%s' "$CV_HTTP_BODY" | jq -e 'has("token") or has("user")' >/dev/null; then
  cv_fail "expected no token or user on failure got $CV_HTTP_BODY" $LINENO
fi
if printf '%s' "$CV_HTTP_BODY" | grep -qF "$PASSWORD"; then
  cv_fail "expected submitted password absent from response" $LINENO
fi

# Cleanup
cv_step Cleanup "nothing was created" $LINENO
echo "Nothing to clean up"

echo "CODEVALID_TEST_ASSERTION_OK:login_unregistered_email"
