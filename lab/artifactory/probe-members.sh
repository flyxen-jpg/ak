#!/usr/bin/env bash
source /tmp/rtui.sh; rt_login >/dev/null
try() { printf '%-7s %-55s -> ' "$1" "$2"; rt_send "$1" "$2" "$3" | tr -d '\n' | cut -c1-160; echo; }
try PATCH access/api/ui/groups/developers/members '{"add":["alice","bob"]}'
try PATCH access/api/ui/users/carol '{"groups":["release-managers"]}'
try PUT   access/api/ui/groups/developers '{"groupName":"developers","description":"Entwickler","autoJoin":false,"adminPrivileges":false,"usersInGroup":["alice","bob"]}'
try POST  access/api/ui/users/carol/groups '{"add":["release-managers"]}'
try PUT   access/api/ui/permissions/dev-snapshots '{"name":"dev-snapshots","resources":{"artifact":{"actions":{"users":{},"groups":{"developers":["READ","WRITE","ANNOTATE"]}},"targets":{"maven-snapshots":{"include_patterns":["**"],"exclude_patterns":[]},"generic-files":{"include_patterns":["**"],"exclude_patterns":["isos/**"]}}}}}'
for u in alice bob carol; do echo "   $u: $(rt_get access/api/ui/users/$u | jq -c '.groups')"; done
echo test > /tmp/p.txt
echo "   bob->snapshots: $(curl -s -o /dev/null -w '%{http_code}' -u 'bob:Lab-Passw0rd-bob!' -T /tmp/p.txt http://localhost:8082/artifactory/maven-snapshots/perm-test/bob.txt) (erwartet 201)"
echo "   bob->releases:  $(curl -s -o /dev/null -w '%{http_code}' -u 'bob:Lab-Passw0rd-bob!' -T /tmp/p.txt http://localhost:8082/artifactory/maven-releases/perm-test/bob.txt) (erwartet 403)"
echo "   carol->releases: $(curl -s -o /dev/null -w '%{http_code}' -u 'carol:Lab-Passw0rd-carol!' -T /tmp/p.txt http://localhost:8082/artifactory/maven-releases/perm-test/carol.txt) (erwartet 201)"
