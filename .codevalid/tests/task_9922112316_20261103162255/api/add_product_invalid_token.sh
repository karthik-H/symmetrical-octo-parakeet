#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"
# The app's JWT_SECRET from .codevalid/docker-compose.yml (app service).
JWT_SECRET="codevalid-test-jwt-secret"

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
sign_hs256() {
  # $1 payload json, $2 secret
  local h p s
  h=$(printf '%s' '{"alg":"HS256","typ":"JWT"}' | b64url)
  p=$(printf '%s' "$1" | b64url)
  s=$(printf '%s' "$h.$p" | openssl dgst -sha256 -hmac "$2" -binary | b64url)
  printf '%s.%s.%s' "$h" "$p" "$s"
}
count_named() {
  # $1 name; sets COUNT
  cv_http GET /products 200
  COUNT=$(printf '%s' "$CV_HTTP_BODY" | jq --arg n "$1" '[.products[] | select(.name == $n)] | length')
}

# Given
cv_step Given "a set of malformed, unverifiable and stale bearer tokens" $LINENO
command -v openssl >/dev/null || cv_fail "expected openssl in seed-test to sign tokens got none" $LINENO
cv_http POST /auth/register "$(jq -nc --arg e "invalid.tok.${SUFFIX}@example.com" --arg p "Passw0rd!${SUFFIX: -6}" '{email:$e,password:$p}')"
[ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected registration 201 got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO
REAL_TOKEN=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.token')
NOW=$(date +%s)
MALFORMED="not-a-jwt-${SUFFIX}"
TAMPERED="${REAL_TOKEN%?}$( [ "${REAL_TOKEN: -1}" = "A" ] && echo B || echo A )"
WRONG_SECRET=$(sign_hs256 "{\"sub\":\"x\",\"iat\":$NOW}" "wrong-secret-${SUFFIX}")
NUMERIC_SUB=$(sign_hs256 "{\"sub\":12345,\"iat\":$NOW}" "$JWT_SECRET")
UNKNOWN_USER=$(sign_hs256 "{\"sub\":\"33333333-3333-4333-8333-${SUFFIX: -12}\",\"email\":\"gone@example.com\",\"iat\":$NOW}" "$JWT_SECRET")
EXPIRED=$(sign_hs256 "{\"sub\":\"x\",\"iat\":$((NOW-7200)),\"exp\":$((NOW-3600))}" "$JWT_SECRET")
PNAME="Invalid Token Product ${SUFFIX}"
BODY=$(jq -nc --arg n "$PNAME" '{name:$n,description:"should not be stored",price:1}')

# When
cv_step When "POST /products is sent with each invalid token" $LINENO
RESULTS=()
for label in MALFORMED TAMPERED WRONG_SECRET NUMERIC_SUB UNKNOWN_USER EXPIRED; do
  cv_http POST /products "$BODY" -H "Authorization: Bearer ${!label}"
  RESULTS+=("$label|$CV_HTTP_STATUS|$(printf '%s' "$CV_HTTP_BODY" | jq -r '.error // empty' 2>/dev/null)")
done

# Then
cv_step Then "every attempt is 401 Invalid token and no product is created" $LINENO
for r in "${RESULTS[@]}"; do
  IFS='|' read -r label st err <<<"$r"
  [ "$st" = "401" ] || cv_fail "expected HTTP 401 for $label token got $st" $LINENO
  [ "$err" = "Invalid token" ] || cv_fail "expected error 'Invalid token' for $label token got '$err'" $LINENO
done
count_named "$PNAME"
[ "$COUNT" = "0" ] || cv_fail "expected no product named '$PNAME' in catalog got $COUNT" $LINENO

# Cleanup
cv_step Cleanup "nothing created besides the in-memory test account (no delete route)" $LINENO
echo "Nothing to clean up"

echo "CODEVALID_TEST_ASSERTION_OK:add_product_invalid_token"
