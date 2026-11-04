#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"
EMAIL="product_get_${SUFFIX}@example.com"
PASSWORD="Password123!"

# Given
cv_step Given "register a seller and create a product through the API" $LINENO
cv_prereq "register seller $EMAIL" $LINENO
BODY=$(jq -n --arg e "$EMAIL" --arg p "$PASSWORD" '{email:$e,password:$p,name:"Detail Seller"}')
cv_http POST /auth/register "$BODY" 201
TOKEN=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.token // empty')
[ -n "$TOKEN" ] || cv_fail "expected token from /auth/register got: $CV_HTTP_BODY" $LINENO

cv_prereq "create product" $LINENO
NAME="Detail Item ${SUFFIX}"
DESC="Detailed description ${SUFFIX}"
BODY=$(jq -n --arg n "$NAME" --arg d "$DESC" '{name:$n,description:$d,price:12.34}')
cv_http POST /products "$BODY" 201 -H "Authorization: Bearer $TOKEN"
PID=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.product.id // empty')
[ -n "$PID" ] || cv_fail "expected product.id got: $CV_HTTP_BODY" $LINENO

# When
cv_step When "open the product by id without signing in" $LINENO
cv_http GET "/products/${PID}"

# Then
cv_step Then "200 with the product's details" $LINENO
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected HTTP 200 got $CV_HTTP_STATUS" $LINENO
GOT_ID=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.product.id // empty')
[ "$GOT_ID" = "$PID" ] || cv_fail "expected product.id '$PID' got '$GOT_ID'" $LINENO
GOT_NAME=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.product.name // empty')
[ "$GOT_NAME" = "$NAME" ] || cv_fail "expected product.name '$NAME' got '$GOT_NAME'" $LINENO
GOT_DESC=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.product.description // empty')
[ "$GOT_DESC" = "$DESC" ] || cv_fail "expected product.description '$DESC' got '$GOT_DESC'" $LINENO
PRICE_OK=$(printf '%s' "$CV_HTTP_BODY" | jq '.product.price == 12.34')
[ "$PRICE_OK" = "true" ] || cv_fail "expected product.price 12.34 got $(printf '%s' "$CV_HTTP_BODY" | jq -c '.product.price')" $LINENO

# Cleanup
cv_step Cleanup "nothing to remove: products live in the in-memory store and the API has no delete route" $LINENO
echo "Created product $PID is kept in memory only (reset on stack restart)"

echo "CODEVALID_TEST_ASSERTION_OK:get_product_by_id_public_access"
