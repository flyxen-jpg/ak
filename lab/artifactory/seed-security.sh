#!/usr/bin/env bash
# Nachtrag Security (Gruppen/Mitgliedschaften/Permissions) fuer den bereits befuellten Stand
source /tmp/rtui.sh; echo "login $(rt_login)"
rt_send POST access/api/ui/groups '{"groupName":"release-managers","description":"Release-Team","autoJoin":false,"adminPrivileges":false}' | tr -d '\n'; echo
echo "== Mitgliedschaften pruefen"
for u in alice bob carol; do echo "   $u: $(rt_get access/api/ui/users/$u | jq -c '.groups')"; done
echo "== User mit Gruppen neu anlegen (falls Gruppen fehlen)"
for u in alice:developers bob:developers carol:release-managers; do
  n=${u%%:*}; g=${u#*:}
  if ! rt_get access/api/ui/users/$n | jq -e --arg g "$g" '.groups | index($g)' >/dev/null; then
    rt_send DELETE access/api/ui/users/$n '' | tail -1
    rt_send POST access/api/ui/users "{\"username\":\"$n\",\"email\":\"$n@lab.local\",\"password\":\"Lab-Passw0rd-$n!\",\"admin\":false,\"profileUpdatable\":true,\"disableUiAccess\":false,\"internalPasswordDisabled\":false,\"groups\":[\"$g\"]}" | tail -1
  fi
done
echo "== Permissions"
rt_send DELETE access/api/ui/permissions/dev-snapshots '' | tail -1
rt_send POST access/api/ui/permissions '{"name":"dev-snapshots","resources":{"artifact":{"actions":{"users":{},"groups":{"developers":["READ","WRITE","ANNOTATE"]}},"targets":{"maven-snapshots":{"include_patterns":["**"],"exclude_patterns":[]},"generic-files":{"include_patterns":["**"],"exclude_patterns":["isos/**"]}}}}}' | tr -d '\n'; echo
rt_send POST access/api/ui/permissions '{"name":"release-deploy","resources":{"artifact":{"actions":{"users":{"carol":["READ","WRITE","DELETE"]},"groups":{"release-managers":["READ","WRITE","DELETE","ANNOTATE"],"developers":["READ"]}},"targets":{"maven-releases":{"include_patterns":["**"],"exclude_patterns":[]},"gradle-plugins":{"include_patterns":["**"],"exclude_patterns":[]}}}}}' | tr -d '\n'; echo
echo "== Ergebnis"
for u in alice bob carol; do echo "   $u: $(rt_get access/api/ui/users/$u | jq -c '.groups')"; done
echo "   Gruppen:     $(rt_get access/api/ui/groups | jq -c '[.groups[].name]')"
echo "   Permissions: $(rt_get access/api/ui/permissions | jq -c '[.permissions[].name]')"
echo "== Funktionstest: bob (developers) darf maven-snapshots schreiben, maven-releases nicht"
echo test > /tmp/p.txt
echo "   snapshots: $(curl -s -o /dev/null -w '%{http_code}' -u 'bob:Lab-Passw0rd-bob!' -T /tmp/p.txt http://localhost:8082/artifactory/maven-snapshots/perm-test/bob.txt)  (erwartet 201)"
echo "   releases:  $(curl -s -o /dev/null -w '%{http_code}' -u 'bob:Lab-Passw0rd-bob!' -T /tmp/p.txt http://localhost:8082/artifactory/maven-releases/perm-test/bob.txt)  (erwartet 403)"
