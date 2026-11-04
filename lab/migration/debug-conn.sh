#!/usr/bin/env bash
source ~/ha/lab.conf; source ~/ha/secrets.env
AK=http://$VIP
TOKEN=$(curl -s -X POST $AK/api/v1/auth/login -H 'Content-Type: application/json' -d "{\"username\":\"admin\",\"password\":\"$ADMIN_PASSWORD\"}" | jq -r .access_token)
for p in /migrations/connections /migrations; do
  echo "== GET $p"; curl -s -w '\nHTTP %{http_code}\n' "$AK/api/v1$p" -H "Authorization: Bearer $TOKEN" | head -c 400; echo
done
echo "== POST /migrations/connections"
curl -s -i -X POST "$AK/api/v1/migrations/connections" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d "{\"name\":\"artifactory-oss\",\"url\":\"http://$IP_INFRA:8082/artifactory\",\"auth_type\":\"basic_auth\",\"source_type\":\"artifactory\",\"credentials\":{\"username\":\"admin\",\"password\":\"password\"}}" | head -c 900; echo
