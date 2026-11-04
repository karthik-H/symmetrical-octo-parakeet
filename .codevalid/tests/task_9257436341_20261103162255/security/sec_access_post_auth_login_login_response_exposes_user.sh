#!/usr/bin/env bash
set -uo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"
V_EMAIL="victim.${SUFFIX}@example.com"
V_PASS="VPass!${SUFFIX: -8}"
V_NAME="Victim Person ${SUFFIX: -6}"
TITLE="Login response exposes user profile fields in clear to any successful attacker, increasing impact of credential stuffing"

cv_step Given "register victim V with email and name" $LINENO
cv_http POST /auth/register "$(jq -nc --arg e "$V_EMAIL" --arg p "$V_PASS" --arg n "$V_NAME" '{email:$e,password:$p,name:$n}')"
[ "$CV_HTTP_STATUS" = "201" ] || { echo "setup failed: register V $CV_HTTP_STATUS"; exit 1; }

cv_step When "control: V logs in; attack: anonymous with guessed vs stuffed credentials" $LINENO
cv_http POST /auth/login "$(jq -nc --arg e "$V_EMAIL" --arg p "$V_PASS" '{email:$e,password:$p}')"
C_STATUS="$CV_HTTP_STATUS"
C_KEYS=$(printf '%s' "$CV_HTTP_BODY" | jq -c '.user | keys? // []' 2>/dev/null)
printf 'CV_SECURITY_CONTROL|user|%s|user fields %s\n' "$C_STATUS" "$C_KEYS"

# Attacker without the right password gets nothing; with the compromised password gets what the owner gets.
cv_http POST /auth/login "$(jq -nc --arg e "$V_EMAIL" --arg p "Wrong${V_PASS}" '{email:$e,password:$p}')"
W_STATUS="$CV_HTTP_STATUS"
W_HAS_USER=$(printf '%s' "$CV_HTTP_BODY" | jq -r 'has("user")' 2>/dev/null)
cv_http POST /auth/login "$(jq -nc --arg e "$V_EMAIL" --arg p "$V_PASS" '{email:$e,password:$p}')"
A_STATUS="$CV_HTTP_STATUS"
A_KEYS=$(printf '%s' "$CV_HTTP_BODY" | jq -c '.user | keys? // []' 2>/dev/null)
A_EXTRA=$(printf '%s' "$CV_HTTP_BODY" | jq -r '[.user | to_entries[]? | select(.key != "id" and .key != "email" and .key != "name") | .key] | join(",")' 2>/dev/null)
HAS_SECRET=0
printf '%s' "$CV_HTTP_BODY" | grep -qiE 'password|\$2[aby]\$' && HAS_SECRET=1
printf 'CV_SECURITY_ATTACK|anonymous|%s|wrong-password status %s user=%s; stuffed-credential user fields %s extra=%s secret=%s\n' "$A_STATUS" "$W_STATUS" "$W_HAS_USER" "$A_KEYS" "${A_EXTRA:-none}" "$HAS_SECRET"

# Gain only if the attacker obtains data beyond what holding the credentials already grants
# (the email they typed and the account's own display name), e.g. a password hash, other fields,
# or a profile without a valid password.
if [ "$W_HAS_USER" = "true" ] || [ "$HAS_SECRET" = "1" ] || [ -n "$A_EXTRA" ]; then
  printf 'CV_SECURITY|vulnerable|access|%s|control %s %s vs attack %s %s extra=%s secret=%s wrong-pw user=%s\n' "$TITLE" "$C_STATUS" "$C_KEYS" "$A_STATUS" "$A_KEYS" "${A_EXTRA:-none}" "$HAS_SECRET" "$W_HAS_USER"
else
  printf 'CV_SECURITY|secure|access|%s|control %s and attack %s both return only id email name of the authenticated account and wrong password gets %s with no profile\n' "$TITLE" "$C_STATUS" "$A_STATUS" "$W_STATUS"
fi

cv_step Cleanup "in-memory store has no delete route; data discarded on restart" $LINENO
exit 0
