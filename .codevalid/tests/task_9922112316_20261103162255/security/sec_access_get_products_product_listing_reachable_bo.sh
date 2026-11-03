#!/usr/bin/env bash
set -uo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"
A_EMAIL="catalog.owner.${SUFFIX}@example.com"
A_PASS="APass!${SUFFIX: -8}"
CAT="access"
TITLE="Product listing reachable both with and without authentication may leak user-scoped catalog views"

cv_step Given "sign up user A and add a product via POST /products" $LINENO
cv_http POST /auth/register "$(jq -nc --arg e "$A_EMAIL" --arg p "$A_PASS" '{email:$e,password:$p}')"
[ "$CV_HTTP_STATUS" = "201" ] || { echo "setup failed: register A $CV_HTTP_STATUS"; exit 1; }
A_TOKEN=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.token')

cv_http POST /products "$(jq -nc --arg n "Scoped Product $SUFFIX" '{name:$n,description:"test product",price:25}')" -H "Authorization: Bearer $A_TOKEN"
[ "$CV_HTTP_STATUS" = "201" ] || { echo "setup failed: create product $CV_HTTP_STATUS"; exit 1; }
PID=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.product.id')

cv_step When "control: authenticated user A calls GET /products" $LINENO
cv_http GET /products -H "Authorization: Bearer $A_TOKEN"
C_STATUS="$CV_HTTP_STATUS"
C_FOUND=$(printf '%s' "$CV_HTTP_BODY" | jq --arg id "$PID" '[.products[]? | select(.id == $id)] | length' 2>/dev/null)
printf 'CV_SECURITY_CONTROL|user|%s|authenticated listing includes product=%s\n' "$C_STATUS" "${C_FOUND:-0}"

cv_step When "attack: anonymous caller calls GET /products" $LINENO
cv_http GET /products
A_STATUS="$CV_HTTP_STATUS"
A_FOUND=$(printf '%s' "$CV_HTTP_BODY" | jq --arg id "$PID" '[.products[]? | select(.id == $id)] | length' 2>/dev/null)
A_PRIVATE=$(printf '%s' "$CV_HTTP_BODY" | jq -r '[.products[]? | to_entries[] | select(.key != "id" and .key != "name" and .key != "description" and .key != "price" and .key != "createdBy" and .key != "createdAt") | .key] | join(",")' 2>/dev/null)
printf 'CV_SECURITY_ATTACK|anonymous|%s|anonymous listing includes product=%s private_fields=%s\n' "$A_STATUS" "${A_FOUND:-0}" "${A_PRIVATE:-none}"

# Public catalog viewing is explicitly permitted by specification; only vulnerable if private/sensitive fields leak.
if [ -n "$A_PRIVATE" ]; then
  printf 'CV_SECURITY|vulnerable|%s|%s|control %s and anonymous %s leaked non-public fields %s\n' "$CAT" "$TITLE" "$C_STATUS" "$A_STATUS" "$A_PRIVATE"
else
  printf 'CV_SECURITY|secure|%s|%s|control %s and anonymous %s return only public catalog fields as designed with no private user data leaked\n' "$CAT" "$TITLE" "$C_STATUS" "$A_STATUS"
fi

cv_step Cleanup "in-memory store has no delete route; data discarded on restart" $LINENO
exit 0
