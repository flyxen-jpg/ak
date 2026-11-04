#!/usr/bin/env bash
# Dauer-Probe gegen die VIP: alle 0,2 s ein GET /readyz und ein Download einer Testdatei.
# Schreibt jede Antwort mit Zeitstempel + bedienendem Knoten nach <logfile> und fasst am Ende zusammen.
# Aufruf: probe-vip.sh <sekunden> <logfile> [download-pfad]
source ~/ha/lab.conf
DUR=$1; LOG=$2; DL=${3:-}
end=$(( $(date +%s) + DUR )); : > "$LOG"
while [ "$(date +%s)" -lt "$end" ]; do
  ts=$(date +%s.%N | cut -c1-14)
  r=$(curl -s -m 3 -o /dev/null -D - -w 'CODE %{http_code} %{time_total}' "http://$VIP/readyz" 2>/dev/null)
  code=$(echo "$r" | awk '/^CODE/{print $2}'); t=$(echo "$r" | awk '/^CODE/{print $3}')
  be=$(echo "$r" | awk -F': ' 'tolower($1)=="x-ak-backend"{gsub("\r","");print $2}')
  lb=$(echo "$r" | awk -F': ' 'tolower($1)=="x-served-by"{gsub("\r","");print $2}' | cut -d. -f1)
  dl=-
  [ -n "$DL" ] && dl=$(curl -s -m 5 -o /dev/null -w '%{http_code}' "http://$VIP$DL")
  echo "$ts readyz=${code:-000} dl=$dl t=${t:-0} lb=${lb:--} be=${be:--}" >> "$LOG"
  sleep 0.2
done
total=$(wc -l < "$LOG"); fail=$(grep -cvE 'readyz=200' "$LOG"); dlfail=$( [ -n "$DL" ] && grep -cvE 'dl=200' "$LOG" || echo 0)
echo "Requests: $total  readyz-Fehler: $fail  Download-Fehler: $dlfail"
# laengste zusammenhaengende Fehlerphase
awk '{split($2,a,"="); ok=(a[2]=="200"); if(!ok){if(!s)s=$1; e=$1} else if(s){d=e-s; if(d>m)m=d; s=0}} END{if(s){d=e-s; if(d>m)m=d} printf "laengste Unterbrechung: %.1f s\n", m}' "$LOG"
echo "bedienende Backends: $(awk '{print $6}' "$LOG" | sort | uniq -c | tr '\n' ' ')"
echo "VIP-Halter:          $(awk '{print $5}' "$LOG" | sort | uniq -c | tr '\n' ' ')"
