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
cv_step Given "a product added during the current service run" $LINENO
register_user "catalog.runtime.${SUFFIX}@example.com"
PNAME="Runtime Product ${SUFFIX}"
add_product "$PNAME" 5
# A product from a previous run cannot be produced from inside the test container (no restart
# control); an id that was never stored in this run stands in for it.
STALE_ID="11111111-1111-4111-8111-${SUFFIX: -12}"

# When
cv_step When "the catalog listing and the stale identifier are requested" $LINENO
cv_http GET /products
LIST_STATUS="$CV_HTTP_STATUS"; LIST_BODY="$CV_HTTP_BODY"
cv_http GET "/products/$STALE_ID"
STALE_STATUS="$CV_HTTP_STATUS"

# Then
cv_step Then "current-run product is visible and the non-retained one is not" $LINENO
[ "$LIST_STATUS" = "200" ] || cv_fail "expected HTTP 200 got $LIST_STATUS: $LIST_BODY" $LINENO
n=$(printf '%s' "$LIST_BODY" | jq --arg id "$PRODUCT_ID" '[.products[] | select(.id == $id)] | length')
[ "$n" = "1" ] || cv_fail "expected current-run product $PRODUCT_ID listed got $n" $LINENO
n=$(printf '%s' "$LIST_BODY" | jq --arg id "$STALE_ID" '[.products[] | select(.id == $id)] | length')
[ "$n" = "0" ] || cv_fail "expected non-retained id $STALE_ID absent got $n" $LINENO
[ "$STALE_STATUS" = "404" ] || cv_fail "expected 404 for non-retained product got $STALE_STATUS" $LINENO

# Cleanup
cv_step Cleanup "in-memory store has no delete route; data discarded on restart" $LINENO
echo "No delete route; product $PRODUCT_ID left in the in-memory store"

echo "CODEVALID_TEST_ASSERTION_OK:service_runtime_retention_visible_in_catalog"
