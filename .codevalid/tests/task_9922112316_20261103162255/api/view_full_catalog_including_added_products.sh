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
cv_step Given "a signed-in user has added a product while the service is running" $LINENO
register_user "catalog.view.${SUFFIX}@example.com"
CREATOR_ID="$USER_ID"
PNAME="Catalog View Product ${SUFFIX}"
add_product "$PNAME" 19.99

# When
cv_step When "an unauthenticated caller requests the full catalog" $LINENO
cv_http GET /products

# Then
cv_step Then "200 with a products collection containing the added product and its details" $LINENO
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected HTTP 200 got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO
printf '%s' "$CV_HTTP_BODY" | jq -e '.products | type == "array"' >/dev/null || cv_fail "expected products array got $CV_HTTP_BODY" $LINENO
ITEM=$(printf '%s' "$CV_HTTP_BODY" | jq -c --arg id "$PRODUCT_ID" '[.products[] | select(.id == $id)]')
[ "$(printf '%s' "$ITEM" | jq 'length')" = "1" ] || cv_fail "expected product $PRODUCT_ID listed exactly once got $ITEM" $LINENO
[ "$(printf '%s' "$ITEM" | jq -r '.[0].name')" = "$PNAME" ] || cv_fail "expected name '$PNAME' got $ITEM" $LINENO
[ "$(printf '%s' "$ITEM" | jq -r '.[0].description')" = "cv test product" ] || cv_fail "expected description 'cv test product' got $ITEM" $LINENO
[ "$(printf '%s' "$ITEM" | jq -r '.[0].price')" = "19.99" ] || cv_fail "expected price 19.99 got $ITEM" $LINENO
[ "$(printf '%s' "$ITEM" | jq -r '.[0].createdBy')" = "$CREATOR_ID" ] || cv_fail "expected createdBy $CREATOR_ID got $ITEM" $LINENO

# Cleanup
cv_step Cleanup "in-memory store has no delete route; data discarded on restart" $LINENO
echo "No delete route; product $PRODUCT_ID left in the in-memory store"

echo "CODEVALID_TEST_ASSERTION_OK:view_full_catalog_including_added_products"
