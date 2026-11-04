#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"
EMAIL="Happy.${SUFFIX}@Example.com"
EMAIL_LC="happy.${SUFFIX}@example.com"
PASSWORD="Str0ngPass!${SUFFIX: -4}"
NAME="Happy Customer ${SUFFIX: -6}"

# Given
cv_step Given "an email that has never been registered" $LINENO
cv_prereq "login with the unused email is rejected" $LINENO
cv_http POST /auth/login "$(jq -nc --arg e "$EMAIL_LC" --arg p "$PASSWORD" '{email:$e,password:$p}')"
[ "$CV_HTTP_STATUS" = "401" ] || cv_fail "expected unused email to fail login with 401 got $CV_HTTP_STATUS" $LINENO

# When
cv_step When "register with the email, a valid password and a display name" $LINENO
cv_http POST /auth/register "$(jq -nc --arg e "$EMAIL" --arg p "$PASSWORD" --arg n "$NAME" '{email:$e,password:$p,name:$n}')"

# Then
cv_step Then "201 with a token and the public profile only, password stored as a hash" $LINENO
[ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected HTTP 201 got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO
TOKEN=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.token // empty')
[ -n "$TOKEN" ] || cv_fail "expected a non-empty token got none" $LINENO
[ "$(printf '%s' "$TOKEN" | awk -F. '{print NF}')" = "3" ] || cv_fail "expected a JWT-shaped token got '$TOKEN'" $LINENO
UID_=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.user.id // empty')
[ -n "$UID_" ] || cv_fail "expected user.id got none" $LINENO
UEMAIL=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.user.email // empty')
[ "$UEMAIL" = "$EMAIL_LC" ] || cv_fail "expected user.email '$EMAIL_LC' got '$UEMAIL'" $LINENO
UNAME=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.user.name // empty')
[ "$UNAME" = "$NAME" ] || cv_fail "expected user.name '$NAME' got '$UNAME'" $LINENO
KEYS=$(printf '%s' "$CV_HTTP_BODY" | jq -c '.user | keys')
[ "$KEYS" = '["email","id","name"]' ] || cv_fail "expected user keys [email,id,name] got $KEYS" $LINENO
if printf '%s' "$CV_HTTP_BODY" | grep -qiE 'password|\$2[aby]\$'; then
  cv_fail "expected no password or hash in response got: $CV_HTTP_BODY" $LINENO
fi
if printf '%s' "$CV_HTTP_BODY" | grep -qF "$PASSWORD"; then
  cv_fail "expected plaintext password absent from response" $LINENO
fi
cv_prereq "the account can sign in with the same password (stored hash verifies)" $LINENO
cv_http POST /auth/login "$(jq -nc --arg e "$EMAIL_LC" --arg p "$PASSWORD" '{email:$e,password:$p}')"
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected login 200 with the registered password got $CV_HTTP_STATUS" $LINENO
LID=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.user.id // empty')
[ "$LID" = "$UID_" ] || cv_fail "expected login user.id $UID_ got $LID" $LINENO
cv_http POST /auth/login "$(jq -nc --arg e "$EMAIL_LC" --arg p "Wrong${PASSWORD}" '{email:$e,password:$p}')"
[ "$CV_HTTP_STATUS" = "401" ] || cv_fail "expected wrong password to be rejected with 401 got $CV_HTTP_STATUS" $LINENO

# Cleanup
cv_step Cleanup "in-memory store has no delete route; the unique account is discarded on restart" $LINENO
echo "No cleanup route; account $EMAIL_LC left in the in-memory store"

echo "CODEVALID_TEST_ASSERTION_OK:register_happy_path_new_email"
