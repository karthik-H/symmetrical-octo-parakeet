#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"

register_user() {
  # $1 email; sets USER_ID TOKEN
  cv_http POST /auth/register "$(jq -nc --arg e "$1" --arg p "Passw0rd!${SUFFIX: -6}" '{email:$e,password:$p}')"
  [ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected registration 201 got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO
  USER_ID=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.user.id // empty')
  TOKEN=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.token // empty')
  [ -n "$USER_ID" ] && [ -n "$TOKEN" ] || cv_fail "expected user id and token from registration got $CV_HTTP_BODY" $LINENO
}

add_product() {
  # $1 name $2 price; sets PRODUCT_ID
  cv_http POST /products "$(jq -nc --arg n "$1" --argjson p "$2" '{name:$n,description:"cv test product",price:$p}')" -H "Authorization: Bearer $TOKEN"
  [ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected product creation 201 got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO
  PRODUCT_ID=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.product.id // empty')
  [ -n "$PRODUCT_ID" ] || cv_fail "expected product id got $CV_HTTP_BODY" $LINENO
}

# Given
cv_step Given "at least one product exists in the catalog" $LINENO
register_user "catalog.anon.${SUFFIX}@example.com"
add_product "Anon List Product ${SUFFIX}" 3

# When
cv_step When "GET /products is called with no Authorization header" $LINENO
cv_http GET /products

# Then
cv_step Then "200 with the products collection, not 401" $LINENO
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected HTTP 200 got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO
printf '%s' "$CV_HTTP_BODY" | jq -e '.products | type == "array"' >/dev/null || cv_fail "expected products array got $CV_HTTP_BODY" $LINENO
n=$(printf '%s' "$CV_HTTP_BODY" | jq --arg id "$PRODUCT_ID" '[.products[] | select(.id == $id)] | length')
[ "$n" = "1" ] || cv_fail "expected product $PRODUCT_ID in anonymous listing got $n" $LINENO

# Cleanup
cv_step Cleanup "in-memory store has no delete route; data discarded on restart" $LINENO
echo "No delete route; product $PRODUCT_ID left in the in-memory store"

echo "CODEVALID_TEST_ASSERTION_OK:unauthenticated_access_allowed_for_catalog_listing"
