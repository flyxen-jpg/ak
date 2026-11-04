#!/usr/bin/env bash
# Security-Migration Artifactory -> Artifact Keeper (Ersatz fuer die in AK 1.11.11 nicht
# implementierte Migration von Usern/Gruppen/Permissions).
#   Quelle: Artifactory-UI-API (OSS; bei Pro alternativ /api/security/* bzw. /access/api/v2/*)
#   Ziel:   AK-REST-API /api/v1/users|groups|permissions
# Abbildung:
#   User        -> lokaler AK-User (gleiche E-Mail), Passwort NICHT uebertragbar -> generiertes
#                  Einmalpasswort, must_change_password=true (Produktiv: LDAP/OIDC statt lokal)
#   Gruppe      -> AK-Gruppe inkl. Mitglieder
#   Permission  -> je (Repo x Principal) eine AK-Regel; READ->read, WRITE/ANNOTATE->write,
#                  DELETE->delete, MANAGE->admin.  Include/Exclude-Pfadmuster sind in AK NICHT
#                  abbildbar -> Warnung; MODE=strict laesst solche Regeln weg, MODE=broad vergibt
#                  sie fuer das ganze Repo.
set -uo pipefail
source ~/ha/lab.conf; source ~/ha/secrets.env; source /tmp/rtui.sh
MODE=${MODE:-strict}
OUT=${1:-$(ls -d ~/migration/run-* | tail -1)}; F="$OUT/security-migration.txt"
AK=http://$VIP
TOKEN=$(curl -s -X POST $AK/api/v1/auth/login -H 'Content-Type: application/json' \
  -d "{\"username\":\"admin\",\"password\":\"$ADMIN_PASSWORD\"}" | jq -r .access_token)
api() { local m=$1 p=$2; shift 2; curl -s -X "$m" "$AK/api/v1$p" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' "$@"; }
step() { printf '\n\033[1;36m[%s] %s\033[0m\n' "$(date +%T)" "$*" | tee -a "$F"; }
log()  { echo "$*" | tee -a "$F"; }
echo "login Artifactory: $(rt_login)"

step "User (Modus: $MODE)"
: > "$OUT/initial-passwords.txt"; chmod 600 "$OUT/initial-passwords.txt"
for u in $(rt_get access/api/ui/users | jq -r '.users[] | select(.username!="anonymous" and .username!="admin") | .username'); do
  email=$(rt_get "access/api/ui/users/$u" | jq -r '.email // empty')
  [ -z "$email" ] && { log "   $u: keine E-Mail in Artifactory -> uebersprungen (AK braucht E-Mail)"; continue; }
  r=$(api POST /users -d "{\"username\":\"$u\",\"email\":\"$email\",\"display_name\":\"$u\",\"is_admin\":false}")
  if jq -e '.user.id' >/dev/null 2>&1 <<<"$r"; then
    echo "$u $(jq -r '.generated_password' <<<"$r")" >> "$OUT/initial-passwords.txt"
    log "   $u ($email): angelegt, must_change_password=$(jq -r .user.must_change_password <<<"$r")"
  else log "   $u: $(head -c 200 <<<"$r")"; fi
done
declare -A UID_OF; while read -r n id; do UID_OF[$n]=$id; done < <(api GET '/users?per_page=200' | jq -r '.items[] | "\(.username) \(.id)"')

step "Gruppen + Mitglieder"
declare -A GID_OF
for g in $(rt_get access/api/ui/groups | jq -r '.groups[] | select(.name!="readers") | .name'); do
  desc=$(rt_get "access/api/ui/groups/$g" | jq -r '.description // ""')
  gid=$(api POST /groups -d "{\"name\":\"$g\",\"description\":\"$desc\"}" | jq -r '.id // empty')
  [ -z "$gid" ] && gid=$(api GET '/groups?per_page=200' | jq -r --arg g "$g" '.items[] | select(.name==$g) | .id')
  GID_OF[$g]=$gid
  members=$(rt_get access/api/ui/users | jq -r '.users[].username' | while read -r u; do
    rt_get "access/api/ui/users/$u" | jq -e --arg g "$g" '.groups | map(.name) | index($g)' >/dev/null 2>&1 && echo "$u"; done)
  ids=$(for m in $members; do [ -n "${UID_OF[$m]:-}" ] && printf '"%s",' "${UID_OF[$m]}"; done | sed 's/,$//')
  code=$(api POST "/groups/$gid/members" -d "{\"user_ids\":[${ids}]}" -o /dev/null -w '%{http_code}')
  log "   $g: angelegt ($gid), Mitglieder [$(echo $members)] -> HTTP $code"
done

step "Permissions"
declare -A RID_OF; while read -r k id; do RID_OF[$k]=$id; done < <(api GET '/repositories?per_page=200' | jq -r '.items[] | "\(.key) \(.id)"')
map_actions() { jq -c '[.[] | {"READ":"read","WRITE":"write","ANNOTATE":"write","DELETE":"delete","MANAGE":"admin","MANAGED_XRAY_META":null,"DISTRIBUTE":null}[.] | select(.!=null)] | unique'; }
for p in $(rt_get access/api/ui/permissions | jq -r '.permissions[].name' | grep -vE '^(Any Remote|Anything)$'); do
  P=$(rt_get "access/api/ui/permissions/$p")
  for repo in $(jq -r '.resources.artifact.targets | keys[]' <<<"$P"); do
    inc=$(jq -c --arg r "$repo" '.resources.artifact.targets[$r].include_patterns' <<<"$P")
    exc=$(jq -c --arg r "$repo" '.resources.artifact.targets[$r].exclude_patterns' <<<"$P")
    patterned=no; { [ "$inc" != '["**"]' ] || [ "$exc" != '[]' ]; } && patterned=yes
    rid=${RID_OF[$repo]:-}
    if [ -z "$rid" ]; then log "   $p/$repo: Repo fehlt in AK -> Regel entfaellt"; continue; fi
    if [ $patterned = yes ] && [ "$MODE" = strict ]; then
      log "   $p/$repo: Pfadmuster inc=$inc exc=$exc NICHT abbildbar -> Regel weggelassen (strict)"; continue; fi
    [ $patterned = yes ] && log "   $p/$repo: WARNUNG Pfadmuster inc=$inc exc=$exc ignoriert -> gilt fuer ganzes Repo (broad)"
    for kind in users groups; do
      for who in $(jq -r --arg k $kind '.resources.artifact.actions[$k] | keys[]' <<<"$P"); do
        acts=$(jq -c --arg k $kind --arg w "$who" '.resources.artifact.actions[$k][$w]' <<<"$P" | map_actions)
        if [ $kind = users ]; then ptype=user; pid=${UID_OF[$who]:-}; else ptype=group; pid=${GID_OF[$who]:-}; fi
        [ -z "$pid" ] && { log "   $p/$repo/$who: Principal fehlt in AK"; continue; }
        r=$(api POST /permissions -d "{\"principal_type\":\"$ptype\",\"principal_id\":\"$pid\",\"target_type\":\"repository\",\"target_id\":\"$rid\",\"actions\":$acts}")
        log "   $p/$repo: $ptype $who $acts -> $(jq -r 'if .id then "ok" else (.message // .) end' <<<"$r" | head -c 150)"
      done
    done
  done
done
log "   AK-Regeln gesamt: $(api GET '/permissions?per_page=500' | jq '.items | length')"
