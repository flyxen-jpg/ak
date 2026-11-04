#!/usr/bin/env bash
source /tmp/rtui.sh; rt_login >/dev/null
# Mitgliedschaften: PUT auf die Gruppe mit usersInGroup (PATCH/members gibt es in der UI-API nicht)
rt_send PUT access/api/ui/groups/release-managers '{"groupName":"release-managers","description":"Release-Team","autoJoin":false,"adminPrivileges":false,"usersInGroup":["carol"]}' | tail -1
rt_send POST access/api/ui/permissions '{"name":"dev-write","resources":{"artifact":{"actions":{"users":{},"groups":{"developers":["READ","WRITE","ANNOTATE"]}},"targets":{"maven-snapshots":{"include_patterns":["**"],"exclude_patterns":[]},"generic-files":{"include_patterns":["**"],"exclude_patterns":["isos/**"]}}}}}' | tail -1
for u in alice bob carol; do echo "   $u: $(rt_get access/api/ui/users/$u | jq -c '[.groups[].name]')"; done
echo "   Permissions: $(rt_get access/api/ui/permissions | jq -c '[.permissions[].name]')"
echo test > /tmp/p.txt
c() { curl -s -o /dev/null -w '%{http_code}' -u "$1:Lab-Passw0rd-$1!" -T /tmp/p.txt "http://localhost:8082/artifactory/$2"; }
echo "   bob   -> maven-snapshots     $(c bob maven-snapshots/perm-test/bob.txt)   (erwartet 201)"
echo "   bob   -> maven-releases      $(c bob maven-releases/perm-test/bob.txt)   (erwartet 403)"
echo "   bob   -> generic-files/isos  $(c bob generic-files/isos/bob.txt)   (erwartet 403, exclude-pattern)"
echo "   carol -> maven-releases      $(c carol maven-releases/perm-test/carol2.txt)   (erwartet 201)"
# Testdateien wieder entfernen, damit das Manifest stimmt
for p in maven-snapshots/perm-test maven-releases/perm-test; do curl -s -o /dev/null -u admin:password -X DELETE "http://localhost:8082/artifactory/$p"; done
B=http://localhost:8082/artifactory
curl -s -u admin:password -X POST $B/api/search/aql -H 'Content-Type: text/plain' \
  -d 'items.find({"type":"file"}).include("repo","path","name","size","sha256")' \
  | jq -r '.results[] | [.repo, (if .path=="." then .name else .path+"/"+.name end), .size, .sha256] | @tsv' \
  | sort > ~/migration/source-manifest.tsv
echo "== Manifest: $(wc -l < ~/migration/source-manifest.tsv) Dateien"
awk -F'\t' '{c[$1]++; s[$1]+=$3} END {for (r in c) printf "   %-22s %5d Dateien %10.1f MB\n", r, c[r], s[r]/1048576}' ~/migration/source-manifest.tsv | sort
