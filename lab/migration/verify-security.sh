#!/usr/bin/env bash
# Vergleicht Benutzer, Gruppen, Mitgliedschaften und Berechtigungen Artifactory <-> Artifact Keeper
# und prueft, ob die Rechte in AK tatsaechlich durchgesetzt werden.
set -uo pipefail
source ~/ha/lab.conf; source ~/ha/secrets.env
source /tmp/rtui.sh >/dev/null 2>&1 || true
OUT=${1:-$(ls -d ~/migration/run-* | tail -1)}
AK=http://$VIP
TOKEN=$(curl -s -X POST $AK/api/v1/auth/login -H 'Content-Type: application/json' \
  -d "{\"username\":\"admin\",\"password\":\"$ADMIN_PASSWORD\"}" | jq -r .access_token)
api() { curl -s "$AK/api/v1$1" -H "Authorization: Bearer $TOKEN"; }
step() { printf '\n\033[1;36m[%s] %s\033[0m\n' "$(date +%T)" "$*" | tee -a "$OUT/security.txt"; }
log()  { echo "$*" | tee -a "$OUT/security.txt"; }

step "Quelle (Artifactory)"
rt_login >/dev/null
for u in alice bob carol; do log "   User $u: Gruppen $(rt_get access/api/ui/users/$u | jq -c '[.groups[].name]')"; done
rt_get access/api/ui/permissions | jq -r '.permissions[].name' | grep -vE '^(Any Remote|Anything)$' | while read -r p; do
  log "   Permission $p: $(rt_get "access/api/ui/permissions/$p" | jq -c '{targets: (.resources.artifact.targets // {} | map_values({inc: .include_patterns, exc: .exclude_patterns})), users: .resources.artifact.actions.users, groups: .resources.artifact.actions.groups}' 2>/dev/null)"
done

step "Ziel (Artifact Keeper)"
api '/users?per_page=100' > "$OUT/ak-users.json"
api '/groups?per_page=100' > "$OUT/ak-groups.json"
api '/permissions?per_page=100' > "$OUT/ak-permissions.json"
log "   User:   $(jq -c '[(.items // .)[] | {u: .username, admin: (.is_admin // .admin), active: (.is_active // null), src: (.auth_provider // .source // null)}]' "$OUT/ak-users.json")"
log "   Gruppen: $(jq -c '[(.items // .)[] | {name, members: (.member_count // null)}]' "$OUT/ak-groups.json")"
for g in $(jq -r '(.items // .)[] | .id' "$OUT/ak-groups.json"); do
  log "     Gruppe $(api /groups/$g | jq -r .name): Mitglieder $(api /groups/$g/members | jq -c '[(.items // .)[]? | .username // .user_id]' 2>/dev/null)"
done
log "   Permissions (roh):"
jq -c '(.items // .)[]' "$OUT/ak-permissions.json" | cut -c1-400 | sed 's/^/     /' | tee -a "$OUT/security.txt"

step "Login migrierter User mit ihrem Artifactory-Passwort"
for u in alice bob carol; do
  r=$(curl -s -X POST $AK/api/v1/auth/login -H 'Content-Type: application/json' -d "{\"username\":\"$u\",\"password\":\"Lab-Passw0rd-$u!\"}")
  log "   $u: $(jq -c '{login_ok: (.access_token != null), must_change_password, fehler: (.message // null)}' <<<"$r")"
done

step "Admin setzt Test-Passwoerter, dann Rechte-Durchsetzung pruefen"
for u in alice bob carol; do
  id=$(jq -r --arg u "$u" '(.items // .)[] | select(.username==$u) | .id' "$OUT/ak-users.json")
  [ -z "$id" ] && { log "   $u: fehlt in AK"; continue; }
  code=$(curl -s -o /tmp/pw.json -w '%{http_code}' -X POST "$AK/api/v1/users/$id/password" -H "Authorization: Bearer $TOKEN" \
     -H 'Content-Type: application/json' -d "{\"new_password\":\"Ak-Test-Passw0rd-$u!\"}")
  log "   Passwort fuer $u gesetzt: HTTP $code $(head -c 150 /tmp/pw.json)"
done
echo "perm-test $(date)" > /tmp/perm.txt
put() { curl -s -o /dev/null -w '%{http_code}' -u "$1:Ak-Test-Passw0rd-$1!" -X PUT --data-binary @/tmp/perm.txt "$AK/api/v1/repositories/$2/artifacts/$3"; }
get() { curl -s -o /dev/null -w '%{http_code}' -u "$1:Ak-Test-Passw0rd-$1!" "$AK/api/v1/repositories/$2/download/$3"; }
log "   Erwartung laut Artifactory-Rechten  |  Ergebnis in AK"
log "   bob   schreibt generic-files/team/   (dev-write: WRITE)        -> $(put bob generic-files team/bob.txt)"
log "   bob   schreibt generic-files/isos/   (exclude isos/**: VERBOT) -> $(put bob generic-files isos/bob.txt)"
log "   bob   schreibt maven-releases        (nur READ: VERBOT)        -> $(put bob maven-releases com/example/x/1/x-1.txt)"
log "   bob   liest   maven-releases         (READ: ERLAUBT)           -> $(get bob maven-releases com/example/core/1.0.0/core-1.0.0.pom)"
log "   carol schreibt maven-releases        (release-deploy: WRITE)   -> $(put carol maven-releases com/example/y/1/y-1.txt)"
log "   carol schreibt generic-files         (keine Rechte: VERBOT)    -> $(put carol generic-files team/carol.txt)"
log "   alice liest   maven-snapshots        (dev-snapshots: READ)     -> $(get alice maven-snapshots com/example/core/3.0.0-SNAPSHOT/core-3.0.0-20261103.100001-1.pom)"
