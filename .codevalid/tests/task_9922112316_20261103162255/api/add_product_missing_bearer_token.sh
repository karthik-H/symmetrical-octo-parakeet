#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"

count_named() {
  # $1 name; sets COUNT
  cv_http GET /products 200
  COUNT=$(printf '%s' "$CV_HTTP_BODY" | jq --arg n "$1" '[.products[] | select(.name == $n)] | length')
}

# Given
cv_step Given "a valid product body and no Authorization header" $LINENO
PNAME="No Token Product ${SUFFIX}"
BODY=$(jq -nc --arg n "$PNAME" '{name:$n,description:"should not be stored",price:9.5}')

# When
cv_step When "POST /products is sent without a bearer token" $LINENO
cv_http POST /products "$BODY"
S1="$CV_HTTP_STATUS"; B1="$CV_HTTP_BODY"
cv_prereq "also try a non-Bearer Authorization scheme" $LINENO
cv_http POST /products "$BODY" -H "Authorization: Basic dXNlcjpwYXNz"
S2="$CV_HTTP_STATUS"; B2="$CV_HTTP_BODY"

# Then
cv_step Then "401 Missing bearer token and no product created" $LINENO
[ "$S1" = "401" ] || cv_fail "expected HTTP 401 without header got $S1: $B1" $LINENO
[ "$(printf '%s' "$B1" | jq -r '.error // empty')" = "Missing bearer token" ] || cv_fail "expected error 'Missing bearer token' got $B1" $LINENO
[ "$S2" = "401" ] || cv_fail "expected HTTP 401 with Basic scheme got $S2: $B2" $LINENO
count_named "$PNAME"
[ "$COUNT" = "0" ] || cv_fail "expected no product named '$PNAME' in catalog got $COUNT" $LINENO

# Cleanup
cv_step Cleanup "nothing created" $LINENO
echo "Nothing to clean up"

echo "CODEVALID_TEST_ASSERTION_OK:add_product_missing_bearer_token"
