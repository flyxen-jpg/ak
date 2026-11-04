#!/usr/bin/env bash
echo "== HAProxy-Sicht (ak-node2)"
curl -s 'http://192.168.56.12:8404/;csv' | awk -F, '($1=="ak_api"||$1=="s3"||$1=="opensearch") && $2!="FRONTEND" && $2!="BACKEND" {print "  "$1"/"$2" "$18" "$37}'
echo "== node1 /readyz + /health"
curl -s -m 3 http://192.168.56.11:8080/readyz; echo
curl -s -m 5 http://192.168.56.11:8080/health; echo
echo "== node1 Backend-Log (Warnungen/Fehler seit 6 min)"
ssh -o BatchMode=yes -o StrictHostKeyChecking=no 192.168.56.11 true 2>/dev/null || true
