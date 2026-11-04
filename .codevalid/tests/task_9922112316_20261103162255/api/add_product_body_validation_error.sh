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

count_named() {
  # $1 name; sets COUNT
  cv_http GET /products 200
  COUNT=$(printf '%s' "$CV_HTTP_BODY" | jq --arg n "$1" '[.products[] | select(.name == $n)] | length')
}

# Given
cv_step Given "a signed-in user and invalid product bodies" $LINENO
register_user "product.invalid.${SUFFIX}@example.com"
PNAME="Invalid Body Product ${SUFFIX}"

# When
cv_step When "POST /products is sent with missing name and with a non-numeric price" $LINENO
cv_http POST /products '{"description":"no name","price":5}' -H "Authorization: Bearer $TOKEN"
S1="$CV_HTTP_STATUS"; B1="$CV_HTTP_BODY"
cv_http POST /products "$(jq -nc --arg n "$PNAME" '{name:$n,description:"bad price",price:"not-a-number"}')" -H "Authorization: Bearer $TOKEN"
S2="$CV_HTTP_STATUS"; B2="$CV_HTTP_BODY"
cv_http POST /products '{}' -H "Authorization: Bearer $TOKEN"
S3="$CV_HTTP_STATUS"; B3="$CV_HTTP_BODY"

# Then
cv_step Then "400 with field-level details and no product created" $LINENO
[ "$S1" = "400" ] || cv_fail "expected HTTP 400 for missing name got $S1: $B1" $LINENO
[ "$(printf '%s' "$B1" | jq -r '.error // empty')" = "Invalid request" ] || cv_fail "expected error 'Invalid request' got $B1" $LINENO
printf '%s' "$B1" | jq -e '.details.name | type == "array" and length > 0' >/dev/null || cv_fail "expected details.name errors got $B1" $LINENO
[ "$S2" = "400" ] || cv_fail "expected HTTP 400 for string price got $S2: $B2" $LINENO
printf '%s' "$B2" | jq -e '.details.price | type == "array" and length > 0' >/dev/null || cv_fail "expected details.price errors got $B2" $LINENO
[ "$S3" = "400" ] || cv_fail "expected HTTP 400 for empty body got $S3: $B3" $LINENO
printf '%s' "$B3" | jq -e '(.details.name | length > 0) and (.details.price | length > 0)' >/dev/null || cv_fail "expected details for name and price got $B3" $LINENO
count_named "$PNAME"
[ "$COUNT" = "0" ] || cv_fail "expected no product named '$PNAME' in catalog got $COUNT" $LINENO

# Cleanup
cv_step Cleanup "nothing created besides the in-memory test account (no delete route)" $LINENO
echo "Nothing to clean up"

echo "CODEVALID_TEST_ASSERTION_OK:add_product_body_validation_error"
