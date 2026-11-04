#!/usr/bin/env bash
# Funktionstest Artifact Keeper: Health, Login, Repo anlegen, Artefakt hoch-/runterladen
set -uo pipefail
cd "$(dirname "$0")/artifact-keeper"
set -a; . ./.env; set +a
B=http://localhost:${HTTP_PORT:-30080}

echo "== Health";  curl -s $B/health | jq -c '{status,version}'
echo "== Login"
L=$(curl -s -X POST $B/api/v1/auth/login -H 'Content-Type: application/json' \
      -d "{\"username\":\"admin\",\"password\":\"$ADMIN_PASSWORD\"}")
T=$(echo "$L" | jq -r '.access_token // .token // empty')
if [[ -z "$T" ]]; then echo "Login fehlgeschlagen: $L"; exit 1; fi
echo "Token ok (${#T} Zeichen), Antwort-Felder: $(echo "$L" | jq -c 'keys')"
H="Authorization: Bearer $T"

echo "== Repo anlegen (generic, local)"
curl -s -X POST $B/api/v1/repositories -H "$H" -H 'Content-Type: application/json' \
  -d '{"key":"test-generic","name":"test-generic","format":"generic","repo_type":"local","is_public":false}' | jq -c '{id,key,format,repo_type} // .'
echo "== Repos";  curl -s $B/api/v1/repositories -H "$H" | jq -c '[.items[]? // .[]? | .key]'

echo "== Upload"
echo "hallo von podman $(date)" > /tmp/ak-test.txt
curl -s -o /dev/null -w "PUT %{http_code}\n" -X PUT -H "$H" --data-binary @/tmp/ak-test.txt \
  $B/api/v1/repositories/test-generic/artifacts/demo/ak-test.txt
echo "== Download"
curl -s -H "$H" $B/api/v1/repositories/test-generic/download/demo/ak-test.txt; echo
