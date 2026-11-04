#!/usr/bin/env bash
set -uo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"
VICTIM="victim.${SUFFIX}@example.com"
NEWUSER="newuser-not-registered.${SUFFIX}@example.com"
CAT="access"
TITLE="User enumeration via email uniqueness check on registration"

cv_step Given "victim account registered through the app" $LINENO
cv_http POST /auth/register "$(jq -nc --arg e "$VICTIM" '{email:$e,password:"VictimPass123!"}')"
if [ "$CV_HTTP_STATUS" != "201" ]; then echo "setup failed: victim registration got $CV_HTTP_STATUS"; exit 1; fi

cv_step When "control: anonymous registers an unused email" $LINENO
cv_http POST /auth/register "$(jq -nc --arg e "$NEWUSER" '{email:$e,password:"Password123!"}')"
C_STATUS=$CV_HTTP_STATUS
C_SHOW=$(printf '%s' "$CV_HTTP_BODY" | jq -r 'if has("token") then "token+user" else (.error // "no body") end' 2>/dev/null || echo "unparsable")
printf 'CV_SECURITY_CONTROL|anonymous|%s|%s\n' "$C_STATUS" "$C_SHOW"

cv_step When "attack: anonymous registers the victim email" $LINENO
cv_http POST /auth/register "$(jq -nc --arg e "$VICTIM" '{email:$e,password:"AnotherPassword123!"}')"
A_STATUS=$CV_HTTP_STATUS
A_MSG=$(printf '%s' "$CV_HTTP_BODY" | jq -r 'if has("token") then "token+user" else (.error // "no body") end' 2>/dev/null || echo "unparsable")
printf 'CV_SECURITY_ATTACK|anonymous|%s|%s\n' "$A_STATUS" "$A_MSG"

cv_step Then "compare responses" $LINENO
if [ "$C_STATUS" = "201" ] && [ "$A_STATUS" != "$C_STATUS" ] && printf '%s' "$A_MSG" | grep -qiE 'already|exist|registered|taken'; then
  printf 'CV_SECURITY|vulnerable|%s|%s|%s\n' "$CAT" "$TITLE" "unused email got $C_STATUS ($C_SHOW) while registered victim email got $A_STATUS ($A_MSG) so registration reveals which emails have accounts"
else
  printf 'CV_SECURITY|secure|%s|%s|%s\n' "$CAT" "$TITLE" "unused email got $C_STATUS ($C_SHOW) and victim email got $A_STATUS ($A_MSG) with no distinguishing signal"
fi
echo "No delete route; probe accounts remain in the in-memory store until restart"
exit 0
