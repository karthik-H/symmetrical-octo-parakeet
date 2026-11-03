#!/usr/bin/env bash
set -uo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"
U_EMAIL="val.user.${SUFFIX}@example.com"
U_PASS="UPass!${SUFFIX: -8}"
CAT="design"
TITLE="Detailed validation error messages disclose internal field structure"

cv_step Given "register a user for control and prepare anonymous/authenticated invalid payloads" $LINENO
cv_http POST /auth/register "$(jq -nc --arg e "$U_EMAIL" --arg p "$U_PASS" '{email:$e,password:$p}')"
[ "$CV_HTTP_STATUS" = "201" ] || { echo "setup failed: register user $CV_HTTP_STATUS"; exit 1; }
U_TOKEN=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.token')

cv_step When "control: valid POST /products request" $LINENO
cv_http POST /products "$(jq -nc --arg n "Valid Product $SUFFIX" '{name:$n,description:"ok",price:5}')" -H "Authorization: Bearer $U_TOKEN"
C_STATUS="$CV_HTTP_STATUS"
C_HAS_DETAILS=$(printf '%s' "$CV_HTTP_BODY" | jq -r 'has("details")' 2>/dev/null)
printf 'CV_SECURITY_CONTROL|user|%s|has_details=%s\n' "$C_STATUS" "$C_HAS_DETAILS"

cv_step When "attack: send invalid body to POST /products to probe fieldErrors disclosure" $LINENO
cv_http POST /products '{"price":"not-a-number"}'
ANON_STATUS="$CV_HTTP_STATUS"
cv_http POST /products '{"price":"not-a-number"}' -H "Authorization: Bearer $U_TOKEN"
A_STATUS="$CV_HTTP_STATUS"
A_FIELDS=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.details | keys? // [] | join(",")' 2>/dev/null)
printf 'CV_SECURITY_ATTACK|anonymous|%s|anon_status=%s auth_invalid_status=%s details_fields=%s\n' "$A_STATUS" "$ANON_STATUS" "$A_STATUS" "${A_FIELDS:-none}"

if [ -n "$A_FIELDS" ] && printf '%s' "$A_FIELDS" | grep -qE 'name|price'; then
  printf 'CV_SECURITY|vulnerable|%s|%s|control %s has_details=%s while invalid body returned %s with per-field validation details (%s)\n' "$CAT" "$TITLE" "$C_STATUS" "$C_HAS_DETAILS" "$A_STATUS" "$A_FIELDS"
else
  printf 'CV_SECURITY|secure|%s|%s|control %s and invalid request %s returned no internal field structure details\n' "$CAT" "$TITLE" "$C_STATUS" "$A_STATUS"
fi

cv_step Cleanup "in-memory store has no delete route; data discarded on restart" $LINENO
exit 0
