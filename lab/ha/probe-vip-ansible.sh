#!/usr/bin/env bash
# Probe fuer den Ausfalltest des per Ansible gebauten Clusters (laeuft auf ans-ctl, im Clusternetz).
# Alle 0,5 s: GET /readyz und Download des Smoke-Test-Artefakts ueber die VIP.
# Ausgabe CSV: zeit;readyz;download;vip-halter;backend
# Aufruf: AK_AUTH=user:pass [VIP=..] [REPO=..] probe-vip-ansible.sh <sekunden> <artefakt-pfad> > probe.csv
DUR=${1:-180}; ART=${2:?pfad}; VIP=${VIP:-192.168.56.60}; REPO=${REPO:-ansible-smoke-test}
end=$(( $(date +%s) + DUR ))
while [ "$(date +%s)" -lt "$end" ]; do
  t=$(date +%H:%M:%S.%N | cut -c1-12)
  r=$(curl -s -o /dev/null -m 2 -w '%{http_code}' "http://$VIP/readyz")
  h=$(curl -s -u "$AK_AUTH" -D - -o /dev/null -m 3 -w '%{http_code}' "http://$VIP/general/$REPO/$ART")
  code=$(echo "$h" | tail -1)
  by=$(echo "$h" | awk -F': ' 'tolower($1)=="x-served-by"{gsub("\r","");print $2}')
  be=$(echo "$h" | awk -F': ' 'tolower($1)=="x-ak-backend"{gsub("\r","");print $2}')
  echo "$t;$r;$code;$by;$be"
  sleep 0.5
done
