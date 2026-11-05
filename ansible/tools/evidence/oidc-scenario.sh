#!/bin/bash
# End to end test of single sign-on with Keycloak, run on the management VM from ansible/.
# Logs in federated users, uses their API tokens at the registry and then removes a user from
# a group in Keycloak to show when that takes effect. Needs skopeo and socat.
#   tools/evidence/oidc-scenario.sh inventories/natnetwork/group_vars/all/vault.yml
set -uo pipefail
vault=${1:?path to vault.yml}
secret() { ansible-vault view "$vault" | sed -n "s/^$1: \"\(.*\)\"$/\1/p"; }

export IDP_PASSWORD AK_URL=${AK_URL:-http://10.0.10.250} AK_PUBLIC_URL=${AK_PUBLIC_URL:-http://localhost:30090}
IDP_PASSWORD=$(secret vault_keycloak_test_password)
keycloak=${KEYCLOAK_URL:-http://10.0.10.3:8080}
keycloak_admin=$(secret vault_keycloak_admin_password)

# The registry token address in the challenge is the external URL, see tasks/token_proxy.yml.
socat TCP-LISTEN:30090,bind=127.0.0.1,fork,reuseaddr "TCP:${AK_URL#http://}:80" &
proxy=$!
trap 'kill $proxy; find ~ -maxdepth 1 -name ".oidc-token-*" -delete' EXIT
sleep 1

try() {
  local user=$1 action=$2 ref=$3 token
  token=$(cat ~/.oidc-token-"$user")
  if [ "$action" = pull ]; then
    skopeo inspect --raw --tls-verify=false --creds "$user:$token" "docker://localhost:30090/$ref" >/dev/null 2>/tmp/try.err
  else
    skopeo copy -q --src-tls-verify=false --dest-tls-verify=false --src-creds "$user:$token" --dest-creds "$user:$token" \
      docker://localhost:30090/docker-base/busybox:1.37.0 "docker://localhost:30090/$ref" >/dev/null 2>/tmp/try.err
  fi
  if [ $? -eq 0 ]; then echo "  $user $action $ref ALLOW"; else echo "  $user $action $ref DENY $(tail -c 70 /tmp/try.err)"; fi
}

for user in zoe yusuf anna dora rita; do
  echo "=== login $user"
  python3 tools/evidence/oidc-login.py "$user" 2>&1 | grep -E 'user:|refused|failed|api token' | cut -c1-210
done

echo "=== registry with API token"
try zoe pull docker-base/alpine:3.21.3
try zoe pull docker-prod/web/nginx:1.27.4-alpine
try dora pull docker-base/alpine:3.21.3
try dora pull docker-prod/web/nginx:1.27.4-alpine
try yusuf pull docker-prod/data/redis:7.4.2-alpine
try rita pull docker-prod/data/redis:7.4.2-alpine
try rita push docker-prod/idp-test/rita:1
try yusuf push docker-prod/idp-test/yusuf:1
try anna pull docker-prod/data/redis:7.4.2-alpine

echo "=== remove zoe from team-data in Keycloak"
token=$(curl -s -m 20 -d grant_type=password -d client_id=admin-cli -d username=admin --data-urlencode "password=$keycloak_admin" \
  "$keycloak/realms/master/protocol/openid-connect/token" | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
first_id='import sys,json;print(json.load(sys.stdin)[0]["id"])'
user_id=$(curl -s -H "Authorization: Bearer $token" "$keycloak/admin/realms/lab/users?username=zoe&exact=true" | python3 -c "$first_id")
group_id=$(curl -s -H "Authorization: Bearer $token" "$keycloak/admin/realms/lab/groups?search=team-data" | python3 -c "$first_id")
curl -s -m 20 -o /dev/null -w 'Keycloak answered %{http_code}\n' -X DELETE -H "Authorization: Bearer $token" \
  "$keycloak/admin/realms/lab/users/$user_id/groups/$group_id"

echo "--- before the next login, with the existing token"
try zoe pull docker-base/alpine:3.21.3
python3 tools/evidence/oidc-login.py zoe 2>&1 | grep -E 'failed|refused'
echo "--- after the next login"
try zoe pull docker-base/alpine:3.21.3
