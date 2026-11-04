#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"
EMAIL="leak.${SUFFIX}@example.com"
PASSWORD="Str0ngPass!${SUFFIX: -6}"
WRONG="Guess${SUFFIX: -6}Pw!"
UNKNOWN="leak.unknown.${SUFFIX}@example.com"

check_generic_401() {
  local label="$1" submitted="$2"
  [ "$CV_HTTP_STATUS" = "401" ] || cv_fail "expected HTTP 401 for $label got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO
  local keys err
  keys=$(printf '%s' "$CV_HTTP_BODY" | jq -c 'keys')
  [ "$keys" = '["error"]' ] || cv_fail "expected only an error field for $label got keys $keys" $LINENO
  err=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.error')
  [ "$err" = "Invalid email or password" ] || cv_fail "expected generic message for $label got '$err'" $LINENO
  if printf '%s' "$CV_HTTP_BODY" | grep -qF "$submitted"; then
    cv_fail "expected submitted password absent for $label" $LINENO
  fi
  if printf '%s' "$CV_HTTP_BODY" | grep -qF "$PASSWORD"; then
    cv_fail "expected real password absent for $label" $LINENO
  fi
  if printf '%s' "$CV_HTTP_BODY" | grep -qE '\$2[aby]\$|hint|incorrect password|wrong password|not found|no account|does not exist'; then
    cv_fail "expected no hash, hint or credential-specific wording for $label got $CV_HTTP_BODY" $LINENO
  fi
}

# Given
cv_step Given "a registered account" $LINENO
cv_http POST /auth/register "$(jq -nc --arg e "$EMAIL" --arg p "$PASSWORD" '{email:$e,password:$p}')"
[ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected registration 201 got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO

# When
cv_step When "trigger 401s for an unknown email and for a wrong password" $LINENO
cv_http POST /auth/login "$(jq -nc --arg e "$UNKNOWN" --arg p "$WRONG" '{email:$e,password:$p}')"
S1="$CV_HTTP_STATUS"; B1="$CV_HTTP_BODY"
cv_http POST /auth/login "$(jq -nc --arg e "$EMAIL" --arg p "$WRONG" '{email:$e,password:$p}')"
S2="$CV_HTTP_STATUS"; B2="$CV_HTTP_BODY"

# Then
cv_step Then "both responses are the identical generic message with no password details" $LINENO
CV_HTTP_STATUS="$S1"; CV_HTTP_BODY="$B1"
check_generic_401 "unknown email" "$WRONG"
CV_HTTP_STATUS="$S2"; CV_HTTP_BODY="$B2"
check_generic_401 "wrong password" "$WRONG"
[ "$(printf '%s' "$B1" | jq -cS .)" = "$(printf '%s' "$B2" | jq -cS .)" ] \
  || cv_fail "expected identical bodies got '$B1' vs '$B2'" $LINENO

# Cleanup
cv_step Cleanup "in-memory store has no delete route; data discarded on restart" $LINENO
echo "No delete route; account $EMAIL left in the in-memory store"

echo "CODEVALID_TEST_ASSERTION_OK:login_response_no_password_leak_on_error"
