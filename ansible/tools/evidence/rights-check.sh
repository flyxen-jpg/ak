#!/bin/bash
# Three checks of the rights handling, run on the management VM from ansible/ after
# playbooks/jcr_seed.yml and migrate.yml --tags security -e artifactory_migration_identity_mode=idp:
#   1. Two permission targets for one group on one repository became one rule (read and write).
#   2. idp-cleanup.py removes the rules of a principal instead of leaving them orphaned.
#   3. A local technical account still works while single sign-on is active.
#   tools/evidence/rights-check.sh inventories/natnetwork/group_vars/all/vault.yml <runner address>
set -uo pipefail
vault=${1:?path to vault.yml}
runner=${2:?address of the migration runner}
secret() { ansible-vault view "$vault" | sed -n "s/^$1: \"\(.*\)\"$/\1/p"; }

export AK_URL=${AK_URL:-http://10.0.10.250} AK_PUBLIC_URL=${AK_PUBLIC_URL:-http://localhost:30090}
export IDP_PASSWORD AK_ADMIN_PASSWORD
IDP_PASSWORD=$(secret vault_keycloak_test_password)
AK_ADMIN_PASSWORD=$(secret vault_artifact_keeper_admin_password)

json() { python3 -c "import sys,json;d=json.load(sys.stdin);print($1)"; }
admin_token=$(curl -s -m 20 -H 'Content-Type: application/json' \
  -d "$(python3 -c 'import json,os;print(json.dumps({"username":"admin","password":os.environ["AK_ADMIN_PASSWORD"]}))')" \
  "$AK_URL/api/v1/auth/login" | json 'd["access_token"]')
api() { curl -s -m 30 -H "Authorization: Bearer $admin_token" -H 'Content-Type: application/json' "$@"; }

file_check() {
  local user=$1 method=$2 path=$3 expected=$4 token code
  token=$(cat ~/.oidc-token-"$user")
  if [ "$method" = PUT ]; then
    code=$(echo "rights check $(date +%s)" | curl -s -m 30 -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $token" -X PUT --data-binary @- \
      "$AK_URL/api/v1/repositories/${path%%/*}/artifacts/${path#*/}")
  else
    code=$(curl -s -m 30 -o /dev/null -w '%{http_code}' -L -H "Authorization: Bearer $token" \
      "$AK_URL/api/v1/repositories/${path%%/*}/artifacts/${path#*/}")
  fi
  echo "  $user $method $path: HTTP $code (expected $expected)"
}

echo "=== 1. Merged rule"
api "$AK_URL/api/v1/permissions?per_page=500" | python3 -c '
import sys, json
rules = [r for r in json.load(sys.stdin)["items"] if r.get("target_name") == "generic-tools"]
for r in rules:
    print(" ", r.get("principal_type"), r.get("principal_name"), r.get("target_name"), r.get("actions"))
print("  rules on generic-tools:", len(rules))'
for user in dora rita; do
  python3 tools/evidence/oidc-login.py "$user" 2>&1 | grep -E 'failed|refused'
done
path=generic-tools/rights-check/dora-$(date +%s).txt
file_check dora PUT "$path" 2xx
file_check dora GET "$path" 200
file_check rita GET "$path" 404
file_check rita PUT "generic-tools/rights-check/rita.txt" 403

echo "=== 2. Cleanup removes rules"
repo_id=$(api "$AK_URL/api/v1/repositories?per_page=100" | json '[r["id"] for r in d["items"] if r["key"]=="generic-tools"][0]')
name=cleanup-test-$(date +%s)
group_id=$(api -X POST -d "{\"name\":\"$name\",\"description\":\"evidence\"}" "$AK_URL/api/v1/groups" | json 'd["id"]')
user_id=$(api -X POST -d "{\"username\":\"$name\",\"email\":\"$name@lab.local\",\"display_name\":\"evidence\",\"is_admin\":false}" "$AK_URL/api/v1/users" | json 'd["user"]["id"] if "user" in d else d["id"]')
for principal in "group $group_id" "user $user_id"; do
  set -- $principal
  api -o /dev/null -w "  rule for $1: HTTP %{http_code}\n" -X POST \
    -d "{\"principal_type\":\"$1\",\"principal_id\":\"$2\",\"target_type\":\"repository\",\"target_id\":\"$repo_id\",\"actions\":[\"read\"]}" \
    "$AK_URL/api/v1/permissions"
done
count_rules() { api "$AK_URL/api/v1/permissions?per_page=500" | python3 -c "
import sys, json
items = json.load(sys.stdin)['items']
print('  total', len(items), 'for test principals', sum(r['principal_id'] in ('$group_id', '$user_id') for r in items))"; }
echo "  before:"; count_rules
python3 tools/evidence/idp-cleanup.py --users "$name" --groups "$name" | sed 's/^/  dry run: /'
echo "  after dry run:"; count_rules
python3 tools/evidence/idp-cleanup.py --users "$name" --groups "$name" --apply | sed 's/^/  apply: /'
echo "  after apply:"; count_rules

echo "=== 3. Local technical account with single sign-on active"
ssh -n "$runner" 'sudo cat /root/ak-migrated-users.txt' > ~/.otp-check
chmod 600 ~/.otp-check
otp() { sed -n "s/^$1 //p" ~/.otp-check; }
curl -s -m 20 -o /tmp/local.out -w '  ci-data login: HTTP %{http_code}\n' -H 'Content-Type: application/json' \
  -d "{\"username\":\"ci-data\",\"password\":\"$(otp ci-data)\"}" "$AK_URL/api/v1/auth/login"
python3 -c 'import json;d=json.load(open("/tmp/local.out"));print("  response:", {k:("***" if "token" in k else v) for k,v in d.items()})'
socat TCP-LISTEN:30090,bind=127.0.0.1,fork,reuseaddr "TCP:${AK_URL#http://}:80" &
proxy=$!
trap 'kill $proxy; find ~ -maxdepth 1 \( -name ".oidc-token-*" -o -name ".otp-check" \) -delete; rm -f /tmp/local.out' EXIT
sleep 1
skopeo inspect --raw --tls-verify=false --creds "ci-data:$(otp ci-data)" docker://localhost:30090/docker-base/python:3.13.2-alpine >/dev/null 2>/tmp/try.err \
  && echo '  ci-data pull docker-base: ALLOW' || echo "  ci-data pull docker-base: DENY $(tail -c 90 /tmp/try.err)"
skopeo inspect --raw --tls-verify=false --creds "ci-data:$(otp ci-data)" docker://localhost:30090/docker-prod/data/redis:7.4.2-alpine >/dev/null 2>/tmp/try.err \
  && echo '  ci-data pull docker-prod: ALLOW' || echo "  ci-data pull docker-prod: DENY $(tail -c 90 /tmp/try.err)"

# The account cannot log in any more, so an administrator issues its token.
ci_id=$(api "$AK_URL/api/v1/users?per_page=500" | json '[u["id"] for u in d["items"] if u["username"]=="ci-data"][0]')
ci_token=$(api -X POST -d '{"name":"rights-check","scopes":["read:artifacts"],"expires_in_days":1}' "$AK_URL/api/v1/users/$ci_id/tokens" | json 'd.get("token","")')
if [ -n "$ci_token" ]; then echo '  token issued by the administrator: yes'; else echo '  token issued by the administrator: no'; fi
skopeo inspect --raw --tls-verify=false --creds "ci-data:$ci_token" docker://localhost:30090/docker-base/python:3.13.2-alpine >/dev/null 2>/tmp/try.err \
  && echo '  ci-data pull docker-base with token: ALLOW' || echo "  ci-data pull docker-base with token: DENY $(tail -c 90 /tmp/try.err)"
