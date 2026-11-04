#!/usr/bin/env bash
# Verifiziert eine Migration: jede Datei der Quelle (AQL-Manifest) wird ueber die VIP aus
# Artifact Keeper geladen und per SHA-256 verglichen. Zusaetzlich Repos/User/Gruppen/Permissions.
# Aufruf: verify.sh [run-verzeichnis]
set -uo pipefail
source ~/ha/lab.conf; source ~/ha/secrets.env
OUT=${1:-$(ls -d ~/migration/run-* | tail -1)}
RT=http://localhost:8082/artifactory; RA=(-u admin:password); AK=http://$VIP
TOKEN=$(curl -s -X POST $AK/api/v1/auth/login -H 'Content-Type: application/json' \
  -d "{\"username\":\"admin\",\"password\":\"$ADMIN_PASSWORD\"}" | jq -r .access_token)
api() { curl -s "$AK/api/v1$1" -H "Authorization: Bearer $TOKEN"; }
step() { printf '\n\033[1;36m[%s] %s\033[0m\n' "$(date +%T)" "$*" | tee -a "$OUT/verify.txt"; }
log()  { echo "$*" | tee -a "$OUT/verify.txt"; }

step "Manifest der Quelle (Stand jetzt, per AQL)"
curl -s "${RA[@]}" -X POST $RT/api/search/aql -H 'Content-Type: text/plain' \
  -d 'items.find({"type":"file"}).include("repo","path","name","size","sha256")' \
  | jq -r '.results[] | [.repo, (if .path=="." then .name else .path+"/"+.name end), .size, .sha256] | @tsv' \
  | sort > "$OUT/source-now.tsv"
log "   $(wc -l < "$OUT/source-now.tsv") Dateien in der Quelle"

step "Jede Datei aus AK laden + SHA-256 vergleichen"
: > "$OUT/verify-result.tsv"; ok=0; bad=0; miss=0; n=0
while IFS=$'\t' read -r repo path size sha; do
  n=$((n+1))
  # Remote-Caches heissen in Artifactory <repo>-cache; AK fuehrt sie unter dem Remote-Repo-Key.
  # Geprueft wird ueber die NATIVEN Endpunkte (wie Maven/Gradle/curl-Clients), nicht ueber die
  # REST-Download-API (die ist bei S3-Storage auf 30 Presign-Requests/min/IP begrenzt).
  key=${repo%-cache}
  case "$key" in generic-files|example-repo-local) fmt=general;; *) fmt=maven;; esac
  got=$(curl -s -f -u "admin:$ADMIN_PASSWORD" "$AK/$fmt/$key/$path" | sha256sum | cut -d' ' -f1)
  code=$?
  if [ "$got" = "$sha" ]; then r=OK; ok=$((ok+1))
  elif [ "$got" = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]; then r=FEHLT; miss=$((miss+1))
  else r=ABWEICHUNG; bad=$((bad+1)); fi
  printf '%s\t%s\t%s\t%s\n' "$r" "$repo" "$path" "$size" >> "$OUT/verify-result.tsv"
  [ $((n % 50)) = 0 ] && printf '\r   %d geprueft: OK=%d FEHLT=%d ABWEICHUNG=%d' $n $ok $miss $bad
done < "$OUT/source-now.tsv"
printf '\r'; log "   $n geprueft: OK=$ok  FEHLT=$miss  ABWEICHUNG=$bad"
log "   Nicht OK nach Repo:"; awk -F'\t' '$1!="OK"{print "     "$1" "$2}' "$OUT/verify-result.tsv" | sort | uniq -c | tee -a "$OUT/verify.txt"
awk -F'\t' '$1!="OK"{print "     "$1" "$2"/"$3}' "$OUT/verify-result.tsv" | head -12 | tee -a "$OUT/verify.txt"

step "Geloeschte Quelldatei (file-2.bin) in AK?"
log "   generic-files/releases/batch-0/file-2.bin -> HTTP $(curl -s -o /dev/null -w '%{http_code}' -u "admin:$ADMIN_PASSWORD" "$AK/general/generic-files/releases/batch-0/file-2.bin")  (200 = Loeschung NICHT uebernommen)"
log "   geaenderte Datei batch-0/file-1.bin: Quelle $(curl -s "${RA[@]}" $RT/generic-files/releases/batch-0/file-1.bin | sha256sum | cut -c1-12)  AK $(curl -s -u "admin:$ADMIN_PASSWORD" "$AK/general/generic-files/releases/batch-0/file-1.bin" | sha256sum | cut -c1-12)"

step "Virtuelles Repo maven-all: Mitglieder + Aufloesung"
VID=$(api '/repositories?per_page=100' | jq -r '.items[] | select(.key=="maven-all") | .id')
log "   Mitglieder laut AK: $(api "/repositories/maven-all/members" | jq -c '[(.items // .)[]? | .key // .member_key // .]' 2>/dev/null) $(api "/repositories/$VID" | jq -c '{members: (.members // .virtual_members // null), upstream_url}' 2>/dev/null)"
for p in com/example/core/1.0.0/core-1.0.0.pom junit/junit/4.13.2/junit-4.13.2.pom; do
  log "   maven-all/$p -> $(curl -s -o /dev/null -w '%{http_code}' -u "admin:$ADMIN_PASSWORD" "$AK/maven/maven-all/$p")"
done
log "   Remote maven-central upstream: $(api '/repositories?per_page=100' | jq -c '.items[] | select(.key=="maven-central") | {upstream_url, repo_type}')"

step "Repositories (Typ/Format)"
api '/repositories?per_page=100' | tee "$OUT/ak-repos.json" | jq -r '.items[]? | "   \(.key)  \(.repo_type)/\(.format)  \(.storage_used_bytes // "")"' | tee -a "$OUT/verify.txt"

step "User / Gruppen / Permissions"
log "   User:        $(api '/users?per_page=100' | tee "$OUT/ak-users.json" | jq -c '[.items[]?.username]')"
log "   Gruppen:     $(api '/groups?per_page=100' | tee "$OUT/ak-groups.json" | jq -c '[.items[]? | {name, members: (.member_count // .members // null)}]')"
log "   Permissions: $(api '/permissions?per_page=100' | tee "$OUT/ak-permissions.json" | jq -c '[.items[]? | .name // .id]')"

step "Login eines migrierten Users (alice, Passwort aus Artifactory)"
log "   alice -> $(curl -s -X POST $AK/api/v1/auth/login -H 'Content-Type: application/json' -d '{"username":"alice","password":"Lab-Passw0rd-alice!"}' | jq -c '{ok: (.access_token != null), must_change_password, error: (.message // .error // null)}')"

step "Properties einer Datei (Artifactory: team/build.number/env)"
log "   Quelle: $(curl -s "${RA[@]}" "$RT/api/storage/generic-files/releases/batch-1/file-60.bin?properties" | jq -c .properties)"
AID=$(api "/repositories/generic-files/artifacts?path=releases/batch-1/file-60.bin&per_page=1" | jq -r '.items[0].id // empty')
log "   AK (artifact $AID): $(api "/artifacts/$AID/properties" | jq -c . 2>/dev/null | cut -c1-300)"
