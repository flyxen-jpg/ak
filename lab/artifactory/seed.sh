#!/usr/bin/env bash
# Befuellt Artifactory OSS mit realistischen Testdaten fuer die Migration nach Artifact Keeper.
#   Repos:  maven-releases, maven-snapshots (Maven local), gradle-plugins (Gradle local),
#           generic-files (Generic local), maven-central (Maven remote), maven-all (Maven virtual)
#   Daten:  Maven-GAVs mit POM+JAR, Snapshots, ~300 kleine Dateien, 5 mittlere, 1x 512 MB,
#           Properties (Matrix-Parameter), Remote-Cache (junit, commons-lang3)
#   Security: Gruppen, User, Permission Targets
# Am Ende: Manifest aller Dateien mit SHA-256 (per AQL) nach ~/migration/source-manifest.tsv
set -uo pipefail
source /tmp/rtui.sh
B=http://localhost:8082/artifactory
A=(-u "$RT_USER:$RT_PASS")
until curl -fs http://localhost:8082/router/api/v1/system/health >/dev/null; do sleep 5; done
echo "UI-Login: $(rt_login)"

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

step "Repositories anlegen (UI-API, da REST in OSS = Pro only)"
mk_local() { # key repoType layout extraTypeSpecificJson
  rt_send POST ui/admin/repositories "{\"type\":\"localRepoConfig\",\"general\":{\"repoKey\":\"$1\"},
    \"basic\":{\"layout\":\"$3\",\"includesPattern\":\"**/*\",\"excludesPattern\":\"\"},
    \"advanced\":{\"blackedOut\":false,\"allowContentBrowsing\":false,\"propertySets\":[]},
    \"typeSpecific\":{\"repoType\":\"$2\"$4}}" | tr -d '\n'; echo
}
mk_local maven-releases  Maven   maven-2-default ',"handleReleases":true,"handleSnapshots":false,"snapshotVersionBehavior":"UNIQUE","localChecksumPolicy":"CLIENT","maxUniqueSnapshots":0'
mk_local maven-snapshots Maven   maven-2-default ',"handleReleases":false,"handleSnapshots":true,"snapshotVersionBehavior":"UNIQUE","localChecksumPolicy":"CLIENT","maxUniqueSnapshots":10'
mk_local gradle-plugins  Gradle  maven-2-default ',"handleReleases":true,"handleSnapshots":true,"snapshotVersionBehavior":"UNIQUE","localChecksumPolicy":"CLIENT","maxUniqueSnapshots":0'
mk_local generic-files   Generic simple-default  ''
rt_send POST ui/admin/repositories '{"type":"remoteRepoConfig","general":{"repoKey":"maven-central"},
  "basic":{"layout":"maven-2-default","includesPattern":"**/*","excludesPattern":"","url":"https://repo1.maven.org/maven2/"},
  "advanced":{"blackedOut":false,"allowContentBrowsing":false,"storeArtifactsLocally":true,"propertySets":[],
    "network":{"socketTimeout":15000,"syncProperties":false,"lenientHostAuth":false,"cookieManagement":false},
    "cache":{"keepUnusedArtifactsHours":0,"retrievalCachePeriodSecs":7200,"assumedOfflineLimitSecs":300,"missedRetrievalCachePeriodSecs":1800}},
  "typeSpecific":{"repoType":"Maven","url":"https://repo1.maven.org/maven2/","handleReleases":true,"handleSnapshots":false,"remoteChecksumPolicy":"GEN_IF_ABSENT"}}' | tr -d '\n'; echo
rt_send POST ui/admin/repositories '{"type":"virtualRepoConfig","general":{"repoKey":"maven-all"},
  "basic":{"layout":"maven-2-default","includesPattern":"**/*","excludesPattern":"","selectedRepositories":[
     {"repoName":"maven-releases","type":"local"},{"repoName":"maven-snapshots","type":"local"},{"repoName":"maven-central","type":"remote"}],
     "defaultDeploymentRepo":"maven-releases"},
  "advanced":{"retrieveRemoteArtifacts":true,"hideUnauthorizedResources":false,"signedUrlTtl":90,"priorityResolution":false},
  "typeSpecific":{"repoType":"Maven","pomCleanupPolicy":"discard_active_reference","forceMavenAuthentication":false}}' | tr -d '\n'; echo
rt_send DELETE ui/admin/repositories/probe-maven/delete '' >/dev/null 2>&1
curl -s "${A[@]}" $B/api/repositories | jq -r '.[] | "   \(.key)  [\(.type)/\(.packageType)]"'

put() { # repo pfad datei [matrix-params]
  local sha1 sha256
  sha1=$(sha1sum "$3" | cut -d' ' -f1); sha256=$(sha256sum "$3" | cut -d' ' -f1)
  curl -s -o /dev/null -w '%{http_code}' "${A[@]}" -T "$3" \
    -H "X-Checksum-Sha1: $sha1" -H "X-Checksum-Sha256: $sha256" "$B/$1/$2${4:-}"
}
W=$(mktemp -d); cd "$W"

step "Maven-Releases: 4 Artefakte x 3 Versionen (POM + JAR + sources)"
ok=0; n=0
for a in core api web cli; do for v in 1.0.0 1.1.0 2.0.0; do
  p="com/example/$a/$v"
  cat > pom.xml <<EOF
<project><modelVersion>4.0.0</modelVersion><groupId>com.example</groupId><artifactId>$a</artifactId><version>$v</version><packaging>jar</packaging></project>
EOF
  head -c $(( (RANDOM % 450 + 50) * 1024 )) /dev/urandom > a.jar
  head -c $(( (RANDOM % 100 + 10) * 1024 )) /dev/urandom > s.jar
  for f in "pom.xml:$a-$v.pom" "a.jar:$a-$v.jar" "s.jar:$a-$v-sources.jar"; do
    n=$((n+1)); [ "$(put maven-releases "$p/${f#*:}" "${f%%:*}")" = 201 ] && ok=$((ok+1))
  done
done; done; echo "   $ok/$n hochgeladen"

step "Maven-Snapshots: core 3.0.0-SNAPSHOT (2 Builds)"
for b in 1 2; do
  ts="20261103.10000$b-$b"
  printf '<project><modelVersion>4.0.0</modelVersion><groupId>com.example</groupId><artifactId>core</artifactId><version>3.0.0-SNAPSHOT</version></project>' > pom.xml
  head -c 200000 /dev/urandom > a.jar
  echo "   pom $(put maven-snapshots com/example/core/3.0.0-SNAPSHOT/core-3.0.0-$ts.pom pom.xml)  jar $(put maven-snapshots com/example/core/3.0.0-SNAPSHOT/core-3.0.0-$ts.jar a.jar)"
done

step "Gradle-Plugin"
head -c 300000 /dev/urandom > g.jar
printf '<project><modelVersion>4.0.0</modelVersion><groupId>com.example.gradle</groupId><artifactId>lab-plugin</artifactId><version>0.9.0</version></project>' > pom.xml
echo "   jar $(put gradle-plugins com/example/gradle/lab-plugin/0.9.0/lab-plugin-0.9.0.jar g.jar)  pom $(put gradle-plugins com/example/gradle/lab-plugin/0.9.0/lab-plugin-0.9.0.pom pom.xml)"

step "Generic: 300 kleine Dateien in Unterordnern, mit Properties"
ok=0
for i in $(seq 1 300); do
  head -c $(( (RANDOM % 20 + 1) * 1024 )) /dev/urandom > small.bin
  team=$([ $((i % 2)) = 0 ] && echo platform || echo apps)
  [ "$(put generic-files "releases/batch-$((i / 50))/file-$i.bin" small.bin ";team=$team;build.number=$i;env=prod")" = 201 ] && ok=$((ok+1))
done; echo "   $ok/300 hochgeladen"

step "Generic: 5 mittlere Dateien (5-20 MB) und 1 grosse Datei (512 MB)"
for i in 1 2 3 4 5; do head -c $(( (i * 3 + 2) * 1024 * 1024 )) /dev/urandom > mid.bin; echo "   medium-$i: $(put generic-files "isos/medium-$i.bin" mid.bin ';type=medium')"; done
head -c $((512 * 1024 * 1024)) /dev/urandom > big.bin
t0=$(date +%s); echo "   big-512mb: $(put generic-files "isos/big-512mb.bin" big.bin ';type=large') in $(( $(date +%s) - t0 ))s"

step "Remote-Cache befuellen (maven-central ueber den virtuellen Repo maven-all)"
for p in junit/junit/4.13.2/junit-4.13.2.jar junit/junit/4.13.2/junit-4.13.2.pom \
         org/apache/commons/commons-lang3/3.17.0/commons-lang3-3.17.0.jar org/hamcrest/hamcrest-core/1.3/hamcrest-core-1.3.jar; do
  echo "   $(curl -s -o /dev/null -w '%{http_code}' "${A[@]}" "$B/maven-all/$p")  $p"
done

step "Security: Gruppen, User, Permissions (UI-API / Access)"
# Feldname ist "groupName" (nicht "name"), sonst: "Name cannot be blank"
rt_send POST access/api/ui/groups '{"groupName":"developers","description":"Entwickler","autoJoin":false,"adminPrivileges":false}' | tail -1
rt_send POST access/api/ui/groups '{"groupName":"release-managers","description":"Release-Team","autoJoin":false,"adminPrivileges":false}' | tail -1
for u in alice:developers bob:developers carol:release-managers; do
  rt_send POST access/api/ui/users "{\"username\":\"${u%%:*}\",\"email\":\"${u%%:*}@lab.local\",\"password\":\"Lab-Passw0rd-${u%%:*}!\",\"admin\":false,\"profileUpdatable\":true,\"disableUiAccess\":false,\"internalPasswordDisabled\":false,\"groups\":[\"${u#*:}\"]}" | tail -1
done
rt_send POST access/api/ui/permissions '{"name":"dev-snapshots","resources":{"artifact":{"actions":{"users":{},"groups":{"developers":["READ","WRITE","ANNOTATE"]}},"targets":{"maven-snapshots":{"include_patterns":["**"],"exclude_patterns":[]},"generic-files":{"include_patterns":["**"],"exclude_patterns":["isos/**"]}}}}}' | tail -1
rt_send POST access/api/ui/permissions '{"name":"release-deploy","resources":{"artifact":{"actions":{"users":{"carol":["READ","WRITE","DELETE"]},"groups":{"release-managers":["READ","WRITE","DELETE","ANNOTATE"],"developers":["READ"]}},"targets":{"maven-releases":{"include_patterns":["**"],"exclude_patterns":[]},"gradle-plugins":{"include_patterns":["**"],"exclude_patterns":[]}}}}}' | tail -1
echo "   User:   $(rt_get access/api/ui/users | jq -c '[.users[].username]')"
echo "   Gruppen: $(rt_get access/api/ui/groups | jq -c '[.groups[].name]')"
echo "   Permissions: $(rt_get access/api/ui/permissions | jq -c '[.permissions[].name]')"

step "Manifest der Quelle (AQL) -> ~/migration/source-manifest.tsv"
mkdir -p ~/migration
curl -s "${A[@]}" -X POST $B/api/search/aql -H 'Content-Type: text/plain' \
  -d 'items.find({"type":"file"}).include("repo","path","name","size","sha256")' \
  | jq -r '.results[] | [.repo, (if .path=="." then .name else .path+"/"+.name end), .size, .sha256] | @tsv' \
  | sort > ~/migration/source-manifest.tsv
awk -F'\t' '{c[$1]++; s[$1]+=$3} END {for (r in c) printf "   %-22s %5d Dateien %10.1f MB\n", r, c[r], s[r]/1048576}' ~/migration/source-manifest.tsv | sort
rm -rf "$W"
