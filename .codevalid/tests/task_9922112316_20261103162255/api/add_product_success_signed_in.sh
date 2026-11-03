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
cv_step Given "a user signed in through the registration flow" $LINENO
register_user "product.add.${SUFFIX}@example.com"
CREATOR_ID="$USER_ID"
PNAME="Added Product ${SUFFIX}"
BODY=$(jq -nc --arg n "$PNAME" '{name:$n,description:"A carefully added product",price:12.75}')

# When
cv_step When "the signed-in user adds a product with name, description and price" $LINENO
cv_http POST /products "$BODY" -H "Authorization: Bearer $TOKEN"

# Then
cv_step Then "201 with the created product recorded against the caller and visible in the catalog" $LINENO
[ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected HTTP 201 got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO
PID=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.product.id // empty')
[ -n "$PID" ] || cv_fail "expected product.id got $CV_HTTP_BODY" $LINENO
[ "$(printf '%s' "$CV_HTTP_BODY" | jq -r '.product.name')" = "$PNAME" ] || cv_fail "expected name '$PNAME' got $CV_HTTP_BODY" $LINENO
[ "$(printf '%s' "$CV_HTTP_BODY" | jq -r '.product.description')" = "A carefully added product" ] || cv_fail "expected description echoed got $CV_HTTP_BODY" $LINENO
[ "$(printf '%s' "$CV_HTTP_BODY" | jq -r '.product.price')" = "12.75" ] || cv_fail "expected price 12.75 got $CV_HTTP_BODY" $LINENO
[ "$(printf '%s' "$CV_HTTP_BODY" | jq -r '.product.createdBy')" = "$CREATOR_ID" ] || cv_fail "expected createdBy $CREATOR_ID got $CV_HTTP_BODY" $LINENO
printf '%s' "$CV_HTTP_BODY" | jq -e '.product.createdAt | type == "string" and length > 0' >/dev/null || cv_fail "expected createdAt timestamp got $CV_HTTP_BODY" $LINENO
cv_http GET "/products/$PID"
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected added product retrievable (200) got $CV_HTTP_STATUS" $LINENO
[ "$(printf '%s' "$CV_HTTP_BODY" | jq -r '.product.name')" = "$PNAME" ] || cv_fail "expected stored name '$PNAME' got $CV_HTTP_BODY" $LINENO

# Cleanup
cv_step Cleanup "in-memory store has no delete route; data discarded on restart" $LINENO
echo "No delete route; product $PID left in the in-memory store"

echo "CODEVALID_TEST_ASSERTION_OK:add_product_success_signed_in"
