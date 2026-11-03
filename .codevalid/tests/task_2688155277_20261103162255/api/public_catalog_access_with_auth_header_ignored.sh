#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"
EMAIL="catalog_hdr_${SUFFIX}@example.com"
PASSWORD="Password123!"

# Given
cv_step Given "register a seller and create a product through the API" $LINENO
cv_prereq "register seller $EMAIL" $LINENO
BODY=$(jq -n --arg e "$EMAIL" --arg p "$PASSWORD" '{email:$e,password:$p,name:"Header Seller"}')
cv_http POST /auth/register "$BODY" 201
TOKEN=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.token // empty')
[ -n "$TOKEN" ] || cv_fail "expected token from /auth/register got: $CV_HTTP_BODY" $LINENO

cv_prereq "create product" $LINENO
NAME="Header Item ${SUFFIX}"
BODY=$(jq -n --arg n "$NAME" '{name:$n,description:"Visible regardless of auth header",price:42.5}')
cv_http POST /products "$BODY" 201 -H "Authorization: Bearer $TOKEN"
PID=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.product.id // empty')
[ -n "$PID" ] || cv_fail "expected product.id got: $CV_HTTP_BODY" $LINENO

# When
cv_step When "list the catalog with an invalid Authorization header" $LINENO
cv_http GET /products "" -H "Authorization: Bearer not-a-valid-token-${SUFFIX}"

# Then
cv_step Then "header is ignored: 200 with the full catalog including the created product" $LINENO
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected HTTP 200 got $CV_HTTP_STATUS" $LINENO
IS_ARRAY=$(printf '%s' "$CV_HTTP_BODY" | jq -r '(.products | type) == "array"' 2>/dev/null || echo false)
[ "$IS_ARRAY" = "true" ] || cv_fail "expected products array in body got: $CV_HTTP_BODY" $LINENO
MATCH=$(printf '%s' "$CV_HTTP_BODY" | jq --arg id "$PID" -c '[.products[] | select(.id == $id)] | first // empty')
[ -n "$MATCH" ] || cv_fail "expected product $PID in catalog got: $CV_HTTP_BODY" $LINENO
GOT_NAME=$(printf '%s' "$MATCH" | jq -r '.name')
[ "$GOT_NAME" = "$NAME" ] || cv_fail "expected name '$NAME' got '$GOT_NAME'" $LINENO
HAS_ERR=$(printf '%s' "$CV_HTTP_BODY" | jq -r 'has("error")')
[ "$HAS_ERR" = "false" ] || cv_fail "expected no error field got: $CV_HTTP_BODY" $LINENO

cv_prereq "same catalog is returned without the header" $LINENO
cv_http GET /products 200
NOAUTH_COUNT=$(printf '%s' "$CV_HTTP_BODY" | jq '.products | length')
[ "$NOAUTH_COUNT" -ge 1 ] || cv_fail "expected at least 1 product without header got $NOAUTH_COUNT" $LINENO

# Cleanup
cv_step Cleanup "nothing to remove: products live in the in-memory store and the API has no delete route" $LINENO
echo "Created product $PID is kept in memory only (reset on stack restart)"

echo "CODEVALID_TEST_ASSERTION_OK:public_catalog_access_with_auth_header_ignored"
