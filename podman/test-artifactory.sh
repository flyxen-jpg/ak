#!/usr/bin/env bash
# Funktionstest Artifactory OSS: Health, Ping, Repo anlegen, Artefakt hoch-/runterladen
# Default-Login einer frischen Installation: admin / password
set -uo pipefail
B=http://localhost:8082
A=(-u "admin:${ARTIFACTORY_ADMIN_PASSWORD:-password}")

echo "== Warte auf Router-Health"
for i in $(seq 1 60); do
  curl -fs $B/router/api/v1/system/health >/dev/null && break; sleep 5
done
curl -s $B/router/api/v1/system/health | jq -c '{router: .router.state, services: [.services[] | {(.service_id): .state}]}'
echo "== Ping (8081 direkt / 8082 Router)"
echo "8081: $(curl -s http://localhost:8081/artifactory/api/system/ping)  8082: $(curl -s $B/artifactory/api/system/ping)"
echo "== Version"; curl -s "${A[@]}" $B/artifactory/api/system/version | jq -c '{version,revision}'

# Hinweis: Repos per REST anlegen ist in OSS nicht verfuegbar (nur Pro) -> mitgeliefertes
# generisches Repo "example-repo-local" verwenden; weitere Repos ueber die UI anlegen.
R=example-repo-local
echo "== Upload nach $R"
echo "hallo von podman $(date)" > /tmp/rt-test.txt
curl -s "${A[@]}" -T /tmp/rt-test.txt $B/artifactory/$R/demo/rt-test.txt | jq -c '{repo,path,size,sha256: .checksums.sha256}'
echo "== Download"
curl -s "${A[@]}" $B/artifactory/$R/demo/rt-test.txt
echo "== Repos"; curl -s "${A[@]}" $B/artifactory/api/repositories | jq -c '[.[].key]'
