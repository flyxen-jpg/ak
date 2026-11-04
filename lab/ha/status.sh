#!/usr/bin/env bash
# Gesamtstatus des HA-Clusters (nur HTTP-Abfragen, laeuft auf jeder Lab-VM).
# Live-Ansicht: watch -n2 -c -t ~/ha/status.sh
cd "$(dirname "$0")"; source ./lab.conf
c()  { curl -s --max-time 2 "$@"; }
st() { if [ "$1" = "$2" ]; then printf '\033[32m%-9s\033[0m' "$1"; else printf '\033[31m%-9s\033[0m' "${1:-DOWN}"; fi; }

printf '\033[1m%s  -  %s\033[0m\n\n' "Artifact Keeper HA-Lab" "$(date +%T)"
printf '\033[1m%-10s %-9s %-9s %-9s %-9s %-9s %-9s\033[0m\n' KNOTEN PATRONI AK-READY AK-HEALTH ETCD GARAGE OPENSRCH
for n in "rocky10:$IP_INFRA" "ak-node1:$IP_NODE1" "ak-node2:$IP_NODE2"; do
  name=${n%%:*}; ip=${n#*:}
  et=$(c "http://$ip:2379/health" | jq -r '.health // empty' 2>/dev/null)
  ga=$(c -o /dev/null -w '%{http_code}' "http://$ip:3903/health")
  os=$(c -o /dev/null -w '%{http_code}' "http://$ip:9200/")
  if [ "$name" = rocky10 ]; then
    printf '%-10s %-9s %-9s %-9s ' "$name" - - -
  else
    role=$(c "http://$ip:8008/patroni" | jq -r '.role // empty' 2>/dev/null)
    rdy=$(c -o /dev/null -w '%{http_code}' "http://$ip:8080/readyz")
    hl=$(c "http://$ip:8080/health" | jq -r '.status // empty' 2>/dev/null)
    printf '%-10s ' "$name"
    if [ -n "$role" ]; then printf '\033[32m%-9s\033[0m ' "$role"; else st "" x; printf ' '; fi
    st "$rdy" 200; printf ' '; st "$hl" healthy; printf ' '
  fi
  st "$et" true; printf ' '; st "$ga" 200; printf ' '; st "$os" 200; echo
done
echo
H=$(c -sI "http://$VIP/readyz")
code=$(echo "$H" | awk 'NR==1{print $2}')
printf 'VIP %s: /readyz ' "$VIP"; st "$code" 200
printf '  VIP-Halter: \033[1m%s\033[0m  beantwortet von: %s\n' \
  "$(echo "$H" | awk -F': ' 'tolower($1)=="x-served-by"{gsub("\r","");print $2}')" \
  "$(echo "$H" | awk -F': ' 'tolower($1)=="x-ak-backend"{gsub("\r","");print $2}')"
printf 'OpenSearch: %s\n' "$(c "http://$IP_INFRA:9200/_cluster/health" | jq -r '"\(.status), \(.number_of_nodes) Knoten"' 2>/dev/null)"
printf 'Patroni:    %s\n' "$( (c "http://$IP_NODE1:8008/cluster"; c "http://$IP_NODE2:8008/cluster") | jq -rs 'map(select(.members))[0].members // [] | map("\(.name)=\(.role)/\(.state) TL\(.timeline // "-") lag=\(.lag // 0)") | join("   ")' 2>/dev/null)"
for ip in $IP_NODE1 $IP_NODE2; do
  printf 'HAProxy %s: ' "$ip"
  c "http://$ip:8404/;csv" | awk -F, '$1!~/^#/ && $1!="stats" && $2!="FRONTEND" && $2!="BACKEND" {printf "%s/%s=%s ", $1, substr($2,1,8), $18}'; echo
done
