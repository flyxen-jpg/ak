#!/usr/bin/env bash
# Live-Migration Artifactory OSS -> Artifact Keeper (HA-Cluster ueber VIP) mit Verifikation.
# Laeuft auf rocky10. Ergebnisse/Belege: ~/migration/run-<zeit>/
set -uo pipefail
source ~/ha/lab.conf; source ~/ha/secrets.env
RT=http://$IP_INFRA:8082/artifactory          # Quelle, wie sie der AK-Backend erreicht
RT_LOCAL=http://localhost:8082/artifactory    # Quelle fuer Testschreiber/Manifest
RA=(-u admin:password)
AK=http://$VIP
OUT=~/migration/run-$(date +%Y%m%d-%H%M%S); mkdir -p "$OUT"
REPOS='["maven-releases","maven-snapshots","gradle-plugins","generic-files","maven-central","maven-all"]'

step() { printf '\n\033[1;36m[%s] %s\033[0m\n' "$(date +%T)" "$*" | tee -a "$OUT/log.txt"; }
log()  { echo "$*" | tee -a "$OUT/log.txt"; }
TOKEN=$(curl -s -X POST $AK/api/v1/auth/login -H 'Content-Type: application/json' \
  -d "{\"username\":\"admin\",\"password\":\"$ADMIN_PASSWORD\"}" | jq -r .access_token)
api() { local m=$1 p=$2; shift 2; curl -s -X "$m" "$AK/api/v1$p" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' "$@"; }

wait_job() { # <job-id> <label>
  local id=$1 s
  while :; do
    s=$(api GET /migrations/$id)
    printf '\r   %-10s %-10s %5s/%-5s ok=%-5s fail=%-4s skip=%-5s %6.1f%%  %8.1f MB   ' "$2" \
      "$(jq -r .status <<<"$s")" "$(( $(jq '.completed_items+.failed_items+.skipped_items' <<<"$s") ))" \
      "$(jq -r .total_items <<<"$s")" "$(jq -r .completed_items <<<"$s")" "$(jq -r .failed_items <<<"$s")" \
      "$(jq -r .skipped_items <<<"$s")" "$(jq -r .progress_percent <<<"$s")" \
      "$(jq -r '.transferred_bytes/1048576' <<<"$s")"
    case "$(jq -r .status <<<"$s")" in completed|failed|cancelled|completed_with_errors|partial) echo; break;; esac
    sleep 2
  done
  echo "$s" > "$OUT/job-$2.json"
  log "   -> $(jq -c '{status,total_items,completed_items,failed_items,skipped_items,transferred_mb:(.transferred_bytes/1048576|floor),started_at,finished_at,error_summary}' <<<"$s")"
}

step "0) Ausgangslage"
log "   Quelle: $(curl -s "${RA[@]}" $RT_LOCAL/api/system/version | jq -r .version) / Ziel: $(curl -s $AK/health | jq -r .version) via $AK"
log "   AK-Repos vorher: $(api GET '/repositories?per_page=100' | jq -c '[.items[]?.key]')"

step "1) Quellverbindung anlegen + testen"
CONN=$(api POST /migrations/connections -d "{\"name\":\"artifactory-oss\",\"url\":\"$RT\",\"auth_type\":\"basic_auth\",\"source_type\":\"artifactory\",\"credentials\":{\"username\":\"admin\",\"password\":\"password\"}}")
CID=$(jq -r '.id // empty' <<<"$CONN" 2>/dev/null)
if [ -z "$CID" ]; then log "   FEHLER beim Anlegen der Verbindung: $CONN"; exit 1; fi
log "   connection: $(jq -c '{id,name,url,source_type}' <<<"$CONN")"
api POST /migrations/connections/$CID/test | tee "$OUT/connection-test.json" | jq -c . | sed 's/^/   test: /' | tee -a "$OUT/log.txt"
api GET /migrations/connections/$CID/repositories | tee "$OUT/source-repos.json" | jq -r '.items[]? // .[]? | "   \(.key)  \(.type)/\(.package_type)"' | tee -a "$OUT/log.txt"

step "2) Assessment"
JA=$(api POST /migrations -d "{\"source_connection_id\":\"$CID\",\"job_type\":\"assessment\",\"config\":{\"include_repos\":$REPOS}}" | jq -r .id)
api POST /migrations/$JA/assess >/dev/null
for i in $(seq 1 30); do A=$(api GET /migrations/$JA/assessment); jq -e '.repositories' <<<"$A" >/dev/null 2>&1 && break; sleep 2; done
echo "$A" > "$OUT/assessment.json"
jq -r '"   Artefakte: \(.total_artifacts) (exakt: \(.total_artifacts_exact)), \(.total_size_bytes/1048576|floor) MB, User: \(.users_count), Gruppen: \(.groups_count), Permissions: \(.permissions_count), geschaetzt \(.estimated_duration_seconds)s",
       (.repositories[] | "   - \(.key) [\(.type)/\(.package_type)] \(.artifact_count) Dateien, Kompatibilitaet: \(.compatibility) \(.warnings|join("; "))"),
       "   Warnungen: \(.warnings|join(" | "))", "   Blocker: \(.blockers|join(" | "))"' <<<"$A" | tee -a "$OUT/log.txt"

step "3) Dry-Run"
JD=$(api POST /migrations -d "{\"source_connection_id\":\"$CID\",\"job_type\":\"full\",\"config\":{\"include_repos\":$REPOS,\"dry_run\":true,\"include_cached_remote\":true}}" | jq -r .id)
api POST /migrations/$JD/start >/dev/null; wait_job "$JD" dryrun
log "   AK-Repos nach Dry-Run: $(api GET '/repositories?per_page=100' | jq -c '[.items[]?.key]')"

step "4) Voll-Lauf, waehrend Artifactory weiter beschrieben wird"
T0=$(date -u +%Y-%m-%dT%H:%M:%SZ); log "   T0 = $T0"
( i=0; while [ ! -f "$OUT/stop-writer" ]; do i=$((i+1))
    head -c $(( (RANDOM % 64 + 1) * 1024 )) /dev/urandom > /tmp/live.bin
    curl -s -o /dev/null "${RA[@]}" -T /tmp/live.bin "$RT_LOCAL/generic-files/live/during-full-$i.bin;phase=live"
    sleep 1; done; echo "$i" > "$OUT/writer-count" ) &
sleep 2
# eine bestehende Datei mit neuem Inhalt ueberschreiben (Aenderung waehrend der Migration)
head -c 4096 /dev/urandom > /tmp/changed.bin
curl -s -o /dev/null -w "   ueberschrieben generic-files/releases/batch-0/file-1.bin -> %{http_code}\n" "${RA[@]}" -T /tmp/changed.bin "$RT_LOCAL/generic-files/releases/batch-0/file-1.bin" | tee -a "$OUT/log.txt"
JF=$(api POST /migrations -d "{\"source_connection_id\":\"$CID\",\"job_type\":\"full\",\"config\":{\"include_repos\":$REPOS,\"include_cached_remote\":true,\"include_users\":true,\"include_groups\":true,\"include_permissions\":true,\"conflict_resolution\":\"skip\",\"concurrent_transfers\":4,\"throttle_delay_ms\":0,\"verify_checksums\":true}}" | jq -r .id)
echo "$JF" > "$OUT/full-job-id"
api POST /migrations/$JF/start >/dev/null; wait_job "$JF" full
touch "$OUT/stop-writer"; wait
log "   waehrend des Voll-Laufs in Artifactory neu hochgeladen: $(cat "$OUT/writer-count") Dateien"

step "5) Datei in der Quelle loeschen (Loeschungen werden laut Code NICHT repliziert)"
curl -s -o /dev/null -w "   DELETE generic-files/releases/batch-0/file-2.bin -> %{http_code}\n" "${RA[@]}" -X DELETE "$RT_LOCAL/generic-files/releases/batch-0/file-2.bin" | tee -a "$OUT/log.txt"
head -c 2048 /dev/urandom > /tmp/after.bin
curl -s -o /dev/null -w "   neu nach Voll-Lauf: generic-files/live/after-full.bin -> %{http_code}\n" "${RA[@]}" -T /tmp/after.bin "$RT_LOCAL/generic-files/live/after-full.bin" | tee -a "$OUT/log.txt"

step "6) Delta-Lauf (incremental, date_from = T0)"
JI=$(api POST /migrations -d "{\"source_connection_id\":\"$CID\",\"job_type\":\"incremental\",\"config\":{\"include_repos\":$REPOS,\"include_cached_remote\":true,\"conflict_resolution\":\"skip\",\"date_from\":\"$T0\",\"concurrent_transfers\":4,\"throttle_delay_ms\":0}}" | jq -r .id)
api POST /migrations/$JI/start >/dev/null; wait_job "$JI" delta

step "7) Fehlgeschlagene Items + Berichte sichern"
for j in "$JF:full" "$JI:delta"; do
  api GET "/migrations/${j%%:*}/items?status=failed&per_page=200" > "$OUT/failed-${j#*:}.json"
  api GET "/migrations/${j%%:*}/report" > "$OUT/report-${j#*:}.json"
  log "   ${j#*:}: $(jq '(.items // []) | length' "$OUT/failed-${j#*:}.json") fehlgeschlagene Items"
  jq -r '(.items // [])[] | "     \(.source_path): \(.error_message)"' "$OUT/failed-${j#*:}.json" | sort | uniq -c | sort -rn | head -15 | tee -a "$OUT/log.txt"
done
echo "$CID $JF $JI" > "$OUT/ids"
log "Belege: $OUT"
