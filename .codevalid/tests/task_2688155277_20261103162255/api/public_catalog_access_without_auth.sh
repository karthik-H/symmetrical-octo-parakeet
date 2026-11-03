#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"
EMAIL="catalog_noauth_${SUFFIX}@example.com"
PASSWORD="Password123!"

# Given
cv_step Given "register a seller and create two products through the API" $LINENO
cv_prereq "register seller $EMAIL" $LINENO
BODY=$(jq -n --arg e "$EMAIL" --arg p "$PASSWORD" '{email:$e,password:$p,name:"Catalog Seller"}')
cv_http POST /auth/register "$BODY" 201
TOKEN=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.token // empty')
[ -n "$TOKEN" ] || cv_fail "expected token from /auth/register got: $CV_HTTP_BODY" $LINENO

cv_prereq "create product A" $LINENO
NAME_A="Catalog Item A ${SUFFIX}"
BODY=$(jq -n --arg n "$NAME_A" '{name:$n,description:"First public item",price:19.99}')
cv_http POST /products "$BODY" 201 -H "Authorization: Bearer $TOKEN"
ID_A=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.product.id // empty')
[ -n "$ID_A" ] || cv_fail "expected product.id for product A got: $CV_HTTP_BODY" $LINENO

cv_prereq "create product B" $LINENO
NAME_B="Catalog Item B ${SUFFIX}"
BODY=$(jq -n --arg n "$NAME_B" '{name:$n,description:"Second public item",price:5}')
cv_http POST /products "$BODY" 201 -H "Authorization: Bearer $TOKEN"
ID_B=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.product.id // empty')
[ -n "$ID_B" ] || cv_fail "expected product.id for product B got: $CV_HTTP_BODY" $LINENO

# When
cv_step When "list the product catalog without any Authorization header" $LINENO
cv_http GET /products

# Then
cv_step Then "catalog is returned with 200 and contains every created product" $LINENO
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected HTTP 200 got $CV_HTTP_STATUS" $LINENO
IS_ARRAY=$(printf '%s' "$CV_HTTP_BODY" | jq -r '(.products | type) == "array"' 2>/dev/null || echo false)
[ "$IS_ARRAY" = "true" ] || cv_fail "expected products array in body got: $CV_HTTP_BODY" $LINENO
for pair in "$ID_A|$NAME_A|19.99|First public item" "$ID_B|$NAME_B|5|Second public item"; do
  IFS='|' read -r PID PNAME PPRICE PDESC <<<"$pair"
  MATCH=$(printf '%s' "$CV_HTTP_BODY" | jq --arg id "$PID" -c '[.products[] | select(.id == $id)] | first // empty')
  [ -n "$MATCH" ] || cv_fail "expected product $PID in catalog got: $CV_HTTP_BODY" $LINENO
  GOT_NAME=$(printf '%s' "$MATCH" | jq -r '.name')
  [ "$GOT_NAME" = "$PNAME" ] || cv_fail "expected name '$PNAME' got '$GOT_NAME'" $LINENO
  GOT_DESC=$(printf '%s' "$MATCH" | jq -r '.description')
  [ "$GOT_DESC" = "$PDESC" ] || cv_fail "expected description '$PDESC' got '$GOT_DESC'" $LINENO
  PRICE_OK=$(printf '%s' "$MATCH" | jq --argjson p "$PPRICE" '.price == $p')
  [ "$PRICE_OK" = "true" ] || cv_fail "expected price $PPRICE got $(printf '%s' "$MATCH" | jq -c '.price')" $LINENO
done

# Cleanup
cv_step Cleanup "nothing to remove: products live in the in-memory store and the API has no delete route" $LINENO
echo "Created products $ID_A and $ID_B are kept in memory only (reset on stack restart)"

echo "CODEVALID_TEST_ASSERTION_OK:public_catalog_access_without_auth"
