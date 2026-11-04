#!/usr/bin/env bash
for u in http://192.168.56.11/readyz http://192.168.56.12/readyz http://192.168.56.100/readyz http://192.168.56.11:8080/readyz; do
  printf '%-36s %s\n' "$u" "$(curl -s -m3 -o /dev/null -w '%{http_code} %{time_total}s' "$u")"
done
ip route get 192.168.56.100
