#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"
EMAIL="invalid.${SUFFIX}@example.com"
PASSWORD="ValidPass!${SUFFIX: -4}"

# check_400 <label> <field>: prints a failure reason, or nothing when the response is a valid 400
check_400() {
  local label="$1" field="$2" err n
  if [ "$CV_HTTP_STATUS" != "400" ]; then echo "[$label] expected HTTP 400 got $CV_HTTP_STATUS: $CV_HTTP_BODY"; return; fi
  err=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.error // empty' 2>/dev/null || true)
  if [ -z "$err" ]; then echo "[$label] expected an error message got: $CV_HTTP_BODY"; return; fi
  n=$(printf '%s' "$CV_HTTP_BODY" | jq -r --arg f "$field" '(.details[$f] // []) | length' 2>/dev/null || echo 0)
  if [ "$n" -lt 1 ]; then echo "[$label] expected details.$field validation messages got: $CV_HTTP_BODY"; return; fi
  if printf '%s' "$CV_HTTP_BODY" | jq -e 'has("token")' >/dev/null 2>&1; then echo "[$label] expected no token got: $CV_HTTP_BODY"; fi
}

# Given
cv_step Given "an unused email and a valid password used to build invalid bodies" $LINENO
cv_http POST /auth/login "$(jq -nc --arg e "$EMAIL" --arg p "$PASSWORD" '{email:$e,password:$p}')"
[ "$CV_HTTP_STATUS" = "401" ] || cv_fail "expected unused email to be unknown (401) got $CV_HTTP_STATUS" $LINENO

# When
cv_step When "register with missing email, missing password and malformed email" $LINENO
cv_http POST /auth/register "$(jq -nc --arg p "$PASSWORD" '{password:$p}')"
S1=$CV_HTTP_STATUS; B1=$CV_HTTP_BODY
cv_http POST /auth/register "$(jq -nc --arg e "$EMAIL" '{email:$e}')"
S2=$CV_HTTP_STATUS; B2=$CV_HTTP_BODY
cv_http POST /auth/register "$(jq -nc --arg p "$PASSWORD" '{email:"not-an-email",password:$p}')"
S3=$CV_HTTP_STATUS; B3=$CV_HTTP_BODY

# Then
cv_step Then "each is 400 with an error and per-field details, and no account exists" $LINENO
CV_HTTP_STATUS=$S1; CV_HTTP_BODY=$B1; R=$(check_400 "missing email" email); [ -z "$R" ] || cv_fail "$R" $LINENO
CV_HTTP_STATUS=$S2; CV_HTTP_BODY=$B2; R=$(check_400 "missing password" password); [ -z "$R" ] || cv_fail "$R" $LINENO
CV_HTTP_STATUS=$S3; CV_HTTP_BODY=$B3; R=$(check_400 "malformed email" email); [ -z "$R" ] || cv_fail "$R" $LINENO
cv_http POST /auth/login "$(jq -nc --arg e "$EMAIL" --arg p "$PASSWORD" '{email:$e,password:$p}')"
[ "$CV_HTTP_STATUS" = "401" ] || cv_fail "expected no account for $EMAIL after rejected registrations (401) got $CV_HTTP_STATUS" $LINENO

# Cleanup
cv_step Cleanup "nothing was created" $LINENO
echo "No data created"

echo "CODEVALID_TEST_ASSERTION_OK:register_missing_or_invalid_fields"
