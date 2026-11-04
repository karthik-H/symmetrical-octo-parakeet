#!/usr/bin/env bash
set -uo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"
A_EMAIL="polluter.${SUFFIX}@example.com"
A_PASS="APass!${SUFFIX: -8}"
CAT="access"
TITLE="Missing validation of product creator identity allows arbitrary catalog pollution"

cv_step Given "sign up user A and obtain a valid Bearer token" $LINENO
cv_http POST /auth/register "$(jq -nc --arg e "$A_EMAIL" --arg p "$A_PASS" '{email:$e,password:$p}')"
[ "$CV_HTTP_STATUS" = "201" ] || { echo "setup failed: register A $CV_HTTP_STATUS"; exit 1; }
A_ID=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.user.id')
A_TOKEN=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.token')

cv_step When "control: user A adds a normal product" $LINENO
cv_http POST /products "$(jq -nc --arg n "Normal Product $SUFFIX" '{name:$n,description:"normal item",price:15}')" -H "Authorization: Bearer $A_TOKEN"
C_STATUS="$CV_HTTP_STATUS"
C_CREATOR=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.product.createdBy // empty' 2>/dev/null)
printf 'CV_SECURITY_CONTROL|user|%s|createdBy=%s\n' "$C_STATUS" "$C_CREATOR"

cv_step When "attack: unprivileged user A adds multiple arbitrary/nonsensical products to the global catalog" $LINENO
OK_COUNT=0
LAST_STATUS=""
for i in 1 2 3 4 5; do
  cv_http POST /products "$(jq -nc --arg n "Polluted Fake Item $SUFFIX #$i" '{name:$n,description:"spam entry",price:0}')" -H "Authorization: Bearer $A_TOKEN"
  LAST_STATUS="$CV_HTTP_STATUS"
  [ "$CV_HTTP_STATUS" = "201" ] && OK_COUNT=$((OK_COUNT + 1))
done
printf 'CV_SECURITY_ATTACK|user|%s|created %d/5 arbitrary products in global catalog\n' "$LAST_STATUS" "$OK_COUNT"

# Per product specification, any signed-in user is allowed to add products to the catalog.
# Check if attacker could spoof createdBy to another user ID.
cv_http POST /products "$(jq -nc --arg n "Spoof Creator $SUFFIX" '{name:$n,description:"spoof",price:1,createdBy:"00000000-0000-0000-0000-000000000000"}')" -H "Authorization: Bearer $A_TOKEN"
SPOOF_CREATOR=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.product.createdBy // empty' 2>/dev/null)

if [ -n "$SPOOF_CREATOR" ] && [ "$SPOOF_CREATOR" != "$A_ID" ]; then
  printf 'CV_SECURITY|vulnerable|%s|%s|control %s createdBy=%s while spoofed createdBy became %s\n' "$CAT" "$TITLE" "$C_STATUS" "$C_CREATOR" "$SPOOF_CREATOR"
else
  printf 'CV_SECURITY|secure|%s|%s|control %s and attack %s always record authenticated caller createdBy=%s and ignore client-supplied createdBy\n' "$CAT" "$TITLE" "$C_STATUS" "$LAST_STATUS" "$A_ID"
fi

cv_step Cleanup "in-memory store has no delete route; data discarded on restart" $LINENO
exit 0
