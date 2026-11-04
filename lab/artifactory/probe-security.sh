#!/usr/bin/env bash
source /tmp/rtui.sh; rt_login >/dev/null
echo "== Gruppe (Variante A: UI-Format)"
rt_send POST access/api/ui/groups '{"name":"developers","description":"Entwickler","autoJoin":false,"adminPrivileges":false,"members":[]}'
echo "== Gruppe (Variante B: Access-v2-Format)"
rt_send POST access/api/ui/groups '{"name":"developers","description":"Entwickler","auto_join":false,"admin_privileges":false,"members":[]}'
echo "== Permission (v2)"
rt_send POST access/api/ui/permissions '{"name":"dev-snapshots","resources":{"artifact":{"actions":{"users":{"alice":["READ","WRITE"]},"groups":{}},"targets":{"maven-snapshots":{"include_patterns":["**"],"exclude_patterns":[]}}}}}'
echo "== Virtuelles Repo: Default-Werte"
rt_get ui/admin/repositories/defaultvalues | jq -c '.defaultModels | with_entries(select(.key|test("virtual";"i")))'
echo "== Remote direkt"
curl -s -o /dev/null -w '%{http_code}\n' -u admin:password http://localhost:8082/artifactory/maven-central/junit/junit/4.13.2/junit-4.13.2.pom
