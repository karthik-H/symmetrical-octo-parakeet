#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"
MISSING_ID="00000000-0000-4000-8000-$(printf '%012d' "$((10#${SUFFIX: -12}))")"

# Given
cv_step Given "an identifier that no product has" $LINENO
cv_prereq "confirm $MISSING_ID is not in the catalog" $LINENO
cv_http GET /products 200
PRESENT=$(printf '%s' "$CV_HTTP_BODY" | jq --arg id "$MISSING_ID" '[.products[] | select(.id == $id)] | length')
[ "$PRESENT" = "0" ] || cv_fail "expected id $MISSING_ID to be absent from the catalog got $PRESENT matches" $LINENO

# When
cv_step When "open the non-existent product without signing in" $LINENO
cv_http GET "/products/${MISSING_ID}"

# Then
cv_step Then "404 with 'Product not found' and no authentication requirement" $LINENO
[ "$CV_HTTP_STATUS" = "404" ] || cv_fail "expected HTTP 404 got $CV_HTTP_STATUS" $LINENO
ERR=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.error // empty' 2>/dev/null || true)
[ "$ERR" = "Product not found" ] || cv_fail "expected error 'Product not found' got '$ERR'" $LINENO
if grep -qi '^www-authenticate:' "$CV_HTTP_HEADERS_FILE"; then
  cv_fail "expected no WWW-Authenticate header got one" $LINENO
fi
if printf '%s' "$CV_HTTP_BODY" | grep -qiE 'token|unauthori|sign.?in|login'; then
  cv_fail "expected no authentication requirement in body got: $CV_HTTP_BODY" $LINENO
fi
HAS_PRODUCT=$(printf '%s' "$CV_HTTP_BODY" | jq -r 'has("product")')
[ "$HAS_PRODUCT" = "false" ] || cv_fail "expected no product field got: $CV_HTTP_BODY" $LINENO

# Cleanup
cv_step Cleanup "nothing was created" $LINENO
echo "No data created"

echo "CODEVALID_TEST_ASSERTION_OK:get_product_by_id_not_found"
