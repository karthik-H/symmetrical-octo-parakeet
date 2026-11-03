#!/usr/bin/env bash
set -uo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"
A_EMAIL="jwt.a.${SUFFIX}@example.com"
B_EMAIL="jwt.b.${SUFFIX}@example.com"
A_PASS="APass!${SUFFIX: -8}"
B_PASS="BPass!${SUFFIX: -8}"
TITLE="JWT tokens are signed over a reduced publicUser payload, enabling privilege misuse if toPublicUser omits or misrepresents identity fields"

jwt_payload() {
  local p
  p=$(printf '%s' "$1" | cut -d. -f2 | tr '_-' '/+')
  case $(( ${#p} % 4 )) in 2) p="${p}==" ;; 3) p="${p}=" ;; esac
  printf '%s' "$p" | base64 -d 2>/dev/null
}

cv_step Given "register users A and B" $LINENO
cv_http POST /auth/register "$(jq -nc --arg e "$A_EMAIL" --arg p "$A_PASS" '{email:$e,password:$p}')"
[ "$CV_HTTP_STATUS" = "201" ] || { echo "setup failed: register A $CV_HTTP_STATUS"; exit 1; }
A_ID=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.user.id')
cv_http POST /auth/register "$(jq -nc --arg e "$B_EMAIL" --arg p "$B_PASS" '{email:$e,password:$p}')"
[ "$CV_HTTP_STATUS" = "201" ] || { echo "setup failed: register B $CV_HTTP_STATUS"; exit 1; }
B_ID=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.user.id')

cv_step When "control: A logs in with correct credentials" $LINENO
cv_http POST /auth/login "$(jq -nc --arg e "$A_EMAIL" --arg p "$A_PASS" '{email:$e,password:$p}')"
C_STATUS="$CV_HTTP_STATUS"
A_TOKEN=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.token // empty')
[ -n "$A_TOKEN" ] || { echo "setup failed: control login gave no token ($C_STATUS)"; exit 1; }
A_SUB=$(jwt_payload "$A_TOKEN" | jq -r '.sub // empty')
printf 'CV_SECURITY_CONTROL|anonymous|%s|token sub=%s matches A id=%s\n' "$C_STATUS" "$A_SUB" "$A_ID"

cv_step When "attack: log in as B via crafted inputs (upper-case email, extra id/sub fields) and compare subjects" $LINENO
cv_http POST /auth/login "$(jq -nc --arg e "${B_EMAIL^^}" --arg p "$B_PASS" --arg a "$A_ID" '{email:$e,password:$p,id:$a,sub:$a,name:"guest"}')"
X_STATUS="$CV_HTTP_STATUS"
B_TOKEN=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.token // empty')
B_SUB=""
[ -n "$B_TOKEN" ] && B_SUB=$(jwt_payload "$B_TOKEN" | jq -r '.sub // empty')
# Which user does the middleware treat B's token as? Create a product and read createdBy.
CREATED_BY=""
if [ -n "$B_TOKEN" ]; then
  cv_http POST /products '{"name":"jwt probe","price":1}' -H "Authorization: Bearer $B_TOKEN"
  CREATED_BY=$(printf '%s' "$CV_HTTP_BODY" | jq -r '.product.createdBy // empty' 2>/dev/null)
fi
printf 'CV_SECURITY_ATTACK|anonymous|%s|token sub=%s B id=%s A id=%s product createdBy=%s\n' "$X_STATUS" "$B_SUB" "$B_ID" "$A_ID" "$CREATED_BY"

VULN=0
if [ -z "$A_SUB" ] || [ "$A_SUB" != "$A_ID" ]; then VULN=1; fi
if [ -n "$B_TOKEN" ]; then
  if [ "$B_SUB" != "$B_ID" ] || [ "$B_SUB" = "$A_SUB" ]; then VULN=1; fi
  if [ -n "$CREATED_BY" ] && [ "$CREATED_BY" != "$B_ID" ]; then VULN=1; fi
fi

if [ "$VULN" = "1" ]; then
  printf 'CV_SECURITY|vulnerable|auth|%s|control sub=%s (A=%s) attack sub=%s (B=%s) createdBy=%s\n' "$TITLE" "$A_SUB" "$A_ID" "$B_SUB" "$B_ID" "$CREATED_BY"
else
  printf 'CV_SECURITY|secure|auth|%s|control %s sub equals A id and attack %s sub equals B id with createdBy B and crafted id/sub fields ignored\n' "$TITLE" "$C_STATUS" "$X_STATUS"
fi

cv_step Cleanup "in-memory store has no delete route; data discarded on restart" $LINENO
exit 0
