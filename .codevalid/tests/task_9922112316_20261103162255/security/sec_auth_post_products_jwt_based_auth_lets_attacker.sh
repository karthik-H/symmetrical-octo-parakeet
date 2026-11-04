#!/usr/bin/env bash
set -uo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"
A_EMAIL="forger.a.${SUFFIX}@example.com"
B_EMAIL="forger.b.${SUFFIX}@example.com"
A_PASS="APass!${SUFFIX: -8}"
B_PASS="BPass!${SUFFIX: -8}"
JWT_SECRET="codevalid-test-jwt-secret"
CAT="auth"
TITLE="JWT-based auth lets attacker act as arbitrary user by forging sub claim"

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
sign_hs256() {
  local h p s
  h=$(printf '%s' '{"alg":"HS256","typ":"JWT"}' | b64url)
  p=$(printf '%s' "$1" | b64url)
  s=$(printf '%s' "$h.$p" | openssl dgst -sha256 -hmac "$2" -binary | b64url)
  printf '%s.%s.%s' "$h" "$p" "$s"
}

cv_step Given "register users A and B" $LINENO
cv_http POST /auth/register "$(jq -nc --arg e "$A_EMAIL" --arg p "$A_PASS" '{email:$e,password:$p}')"
[ "$CV_HTTP_STATUS" = "201" ] || { echo "setup failed: register A $CV_HTTP_STATUS"; exit 1; }
A_ID=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.user.id')

cv_http POST /auth/register "$(jq -nc --arg e "$B_EMAIL" --arg p "$B_PASS" '{email:$e,password:$p}')"
[ "$CV_HTTP_STATUS" = "201" ] || { echo "setup failed: register B $CV_HTTP_STATUS"; exit 1; }
B_ID=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.user.id')
B_TOKEN=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.token')

cv_step When "control: B posts a product with B's legitimate token" $LINENO
cv_http POST /products "$(jq -nc --arg n "Control Product $SUFFIX" '{name:$n,description:"legit",price:10}')" -H "Authorization: Bearer $B_TOKEN"
C_STATUS="$CV_HTTP_STATUS"
C_CREATOR=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.product.createdBy // empty' 2>/dev/null)
printf 'CV_SECURITY_CONTROL|user|%s|product.createdBy=%s (B id=%s)\n' "$C_STATUS" "$C_CREATOR" "$B_ID"

cv_step When "attack: anonymous attacker without secret forges a token claiming sub=A_ID" $LINENO
NOW=$(date +%s)
FORGED_TOKEN=$(sign_hs256 "{\"sub\":\"$A_ID\",\"email\":\"$A_EMAIL\",\"iat\":$NOW}" "attacker-guessed-secret-$SUFFIX")
cv_http POST /products "$(jq -nc --arg n "Forged Product $SUFFIX" '{name:$n,description:"forged",price:10}')" -H "Authorization: Bearer $FORGED_TOKEN"
A_STATUS="$CV_HTTP_STATUS"
A_CREATOR=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.product.createdBy // empty' 2>/dev/null)
A_ERR=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.error // empty' 2>/dev/null)
printf 'CV_SECURITY_ATTACK|anonymous|%s|error=%s product.createdBy=%s\n' "$A_STATUS" "${A_ERR:-none}" "${A_CREATOR:-none}"

if [ "$A_STATUS" = "201" ] && [ "$A_CREATOR" = "$A_ID" ]; then
  printf 'CV_SECURITY|vulnerable|%s|%s|control %s createdBy=%s while forged token got %s createdBy=%s\n' "$CAT" "$TITLE" "$C_STATUS" "$C_CREATOR" "$A_STATUS" "$A_CREATOR"
else
  printf 'CV_SECURITY|secure|%s|%s|control %s createdBy=%s while forged token without server secret was rejected with %s (%s)\n' "$CAT" "$TITLE" "$C_STATUS" "$C_CREATOR" "$A_STATUS" "${A_ERR:-none}"
fi

cv_step Cleanup "in-memory store has no delete route; data discarded on restart" $LINENO
exit 0
