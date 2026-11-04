#!/usr/bin/env bash
# Prueft nach der Security-Migration, ob die Rechte in Artifact Keeper so greifen wie in Artifactory.
# Nutzt die Einmalpasswoerter aus initial-passwords.txt, aendert sie (Pflicht bei Erstlogin)
# und testet Lesen/Schreiben ueber die nativen Endpunkte (wie Maven/curl-Clients).
set -uo pipefail
source ~/ha/lab.conf
OUT=${1:-$(ls -d ~/migration/run-* | tail -1)}; F="$OUT/permission-test.txt"
AK=http://$VIP
log() { echo "$*" | tee -a "$F"; }
: > "$F"
log "== Erstlogin + Pflicht-Passwortwechsel"
while read -r u pw; do
  r=$(curl -s -X POST $AK/api/v1/auth/login -H 'Content-Type: application/json' -d "{\"username\":\"$u\",\"password\":\"$pw\"}")
  t=$(jq -r '.access_token // empty' <<<"$r")
  c=$(curl -s -o /dev/null -w '%{http_code}' -X POST $AK/api/v1/users/me/password -H "Authorization: Bearer $t" \
       -H 'Content-Type: application/json' -d "{\"current_password\":\"$pw\",\"new_password\":\"Ak-Neu-Passw0rd-$u!\"}")
  log "   $u: login=$( [ -n "$t" ] && echo ok || echo FEHLER) must_change=$(jq -r .must_change_password <<<"$r") passwortwechsel=HTTP $c"
done < "$OUT/initial-passwords.txt"

echo "perm-test $(date)" > /tmp/perm.txt
w() { curl -s -o /dev/null -w '%{http_code}' -u "$1:Ak-Neu-Passw0rd-$1!" -T /tmp/perm.txt "$AK/$2"; }
r() { curl -s -o /dev/null -w '%{http_code}' -u "$1:Ak-Neu-Passw0rd-$1!" "$AK/$2"; }
chk() { # beschreibung erwartet(ok|deny) ergebnis
  local res=$3 verdict
  if [ "$2" = ok ]; then [[ "$res" =~ ^20 ]] && verdict="OK" || verdict="ABWEICHUNG"
  else [[ "$res" =~ ^(401|403|404)$ ]] && verdict="OK" || verdict="ABWEICHUNG (Rechte zu weit!)"; fi
  log "$(printf '   %-62s erwartet %-5s -> %-4s %s' "$1" "$2" "$res" "$verdict")"
}
log "== Rechte-Matrix (Erwartung = Artifactory-Rechte)"
chk "bob   WRITE generic-files/team/ (dev-write)"            ok   "$(w bob general/generic-files/team/bob.txt)"
chk "bob   WRITE generic-files/isos/ (in RT per exclude verboten)" deny "$(w bob general/generic-files/isos/bob.txt)"
chk "bob   WRITE maven-releases (nur READ)"                  deny "$(w bob maven/maven-releases/com/example/zz/1.0/zz-1.0.pom)"
chk "bob   READ  maven-releases"                             ok   "$(r bob maven/maven-releases/com/example/core/1.0.0/core-1.0.0.pom)"
chk "bob   WRITE maven-snapshots (dev-write)"                ok   "$(w bob maven/maven-snapshots/com/example/zz/1.0-SNAPSHOT/zz-1.0-20261103.120000-1.pom)"
chk "carol WRITE maven-releases (release-deploy)"            ok   "$(w carol maven/maven-releases/com/example/zz/1.0/zz-1.0.pom)"
chk "carol WRITE generic-files (keine Rechte)"               deny "$(w carol general/generic-files/team/carol.txt)"
chk "carol READ  generic-files (keine Rechte, RT: readers)"  ok   "$(r carol general/generic-files/releases/batch-1/file-60.bin)"
chk "alice WRITE maven-snapshots (dev-snapshots user-Regel)" ok   "$(w alice maven/maven-snapshots/com/example/zz/1.0-SNAPSHOT/zz-1.0-20261103.120000-2.pom)"
chk "anonym READ maven-releases"                             deny "$(curl -s -o /dev/null -w '%{http_code}' "$AK/maven/maven-releases/com/example/core/1.0.0/core-1.0.0.pom")"
