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
cv_step Given "a signed-in user adds three distinct products" $LINENO
register_user "catalog.all.${SUFFIX}@example.com"
IDS=()
for i in 1 2 3; do
  add_product "Catalog All ${SUFFIX} #$i" "$i"
  IDS+=("$PRODUCT_ID")
done
NEVER_ADDED="00000000-0000-4000-8000-${SUFFIX: -12}"

# When
cv_step When "anyone requests the catalog listing" $LINENO
cv_http GET /products

# Then
cv_step Then "every added product is listed once, nothing never-added appears, and ids are unique" $LINENO
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected HTTP 200 got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO
for id in "${IDS[@]}"; do
  n=$(printf '%s' "$CV_HTTP_BODY" | jq --arg id "$id" '[.products[] | select(.id == $id)] | length')
  [ "$n" = "1" ] || cv_fail "expected product $id listed once got $n" $LINENO
done
n=$(printf '%s' "$CV_HTTP_BODY" | jq --arg id "$NEVER_ADDED" '[.products[] | select(.id == $id)] | length')
[ "$n" = "0" ] || cv_fail "expected never-added id $NEVER_ADDED absent got $n" $LINENO
n=$(printf '%s' "$CV_HTTP_BODY" | jq --arg s "Catalog All ${SUFFIX} #" '[.products[] | select(.name | startswith($s))] | length')
[ "$n" = "3" ] || cv_fail "expected exactly 3 products from this run's batch got $n" $LINENO
dup=$(printf '%s' "$CV_HTTP_BODY" | jq '[.products[].id] | (length - (unique | length))')
[ "$dup" = "0" ] || cv_fail "expected unique product ids got $dup duplicates" $LINENO

# Cleanup
cv_step Cleanup "in-memory store has no delete route; data discarded on restart" $LINENO
echo "No delete route; products ${IDS[*]} left in the in-memory store"

echo "CODEVALID_TEST_ASSERTION_OK:catalog_includes_all_current_products"
