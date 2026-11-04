#!/usr/bin/env bash
# Prueft, welche Verwaltungs-APIs Artifactory OSS freigibt
B=http://localhost:8082/artifactory; A=(-u admin:password)
until curl -fs http://localhost:8082/router/api/v1/system/health >/dev/null; do sleep 5; done
echo "== PUT /api/repositories (mit key)"
curl -s "${A[@]}" -X PUT $B/api/repositories/probe-local -H 'Content-Type: application/json' \
  -d '{"key":"probe-local","rclass":"local","packageType":"generic"}'; echo
echo "== PUT /api/security/users"
curl -s "${A[@]}" -X PUT $B/api/security/users/probe -H 'Content-Type: application/json' \
  -d '{"email":"probe@lab.local","password":"Probe-12345!"}'; echo
echo "== POST /access/api/v2/users"
curl -s "${A[@]}" -X POST http://localhost:8082/access/api/v2/users -H 'Content-Type: application/json' \
  -d '{"username":"probe2","password":"Probe-12345!","email":"probe2@lab.local","admin":false}'; echo
echo "== AQL"
curl -s "${A[@]}" -X POST $B/api/search/aql -H 'Content-Type: text/plain' -d 'items.find().limit(2)' | head -c 300; echo
echo "== Access-Token erzeugen"
curl -s "${A[@]}" -X POST http://localhost:8082/access/api/v1/tokens -d 'scope=applied-permissions/admin' -d 'expires_in=0' | jq -c 'del(.access_token)' 2>/dev/null
