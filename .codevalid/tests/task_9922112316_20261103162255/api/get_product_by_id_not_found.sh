#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"

# Given
cv_step Given "an identifier that no product has" $LINENO
MISSING_ID="22222222-2222-4222-8222-${SUFFIX: -12}"
cv_http GET /products 200
n=$(printf '%s' "$CV_HTTP_BODY" | jq --arg id "$MISSING_ID" '[.products[] | select(.id == $id)] | length')
[ "$n" = "0" ] || cv_fail "expected $MISSING_ID not in catalog got $n" $LINENO

# When
cv_step When "the product is requested by that identifier" $LINENO
cv_http GET "/products/$MISSING_ID"

# Then
cv_step Then "404 with a not-found error and no product" $LINENO
[ "$CV_HTTP_STATUS" = "404" ] || cv_fail "expected HTTP 404 got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO
[ "$(printf '%s' "$CV_HTTP_BODY" | jq -r '.error // empty')" = "Product not found" ] || cv_fail "expected error 'Product not found' got $CV_HTTP_BODY" $LINENO
printf '%s' "$CV_HTTP_BODY" | jq -e 'has("product") | not' >/dev/null || cv_fail "expected no product in body got $CV_HTTP_BODY" $LINENO

# Cleanup
cv_step Cleanup "nothing created" $LINENO
echo "Nothing to clean up"

echo "CODEVALID_TEST_ASSERTION_OK:get_product_by_id_not_found"
