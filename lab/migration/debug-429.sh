#!/usr/bin/env bash
source ~/ha/lab.conf; source ~/ha/secrets.env; AK=http://$VIP
TOKEN=$(curl -s -X POST $AK/api/v1/auth/login -H 'Content-Type: application/json' -d "{\"username\":\"admin\",\"password\":\"$ADMIN_PASSWORD\"}" | jq -r .access_token)
for i in $(seq 1 130); do
  r=$(curl -s -D /tmp/h -o /tmp/b -w '%{http_code}' "$AK/api/v1/repositories/generic-files/download/releases/batch-1/file-60.bin" -H "Authorization: Bearer $TOKEN")
  if [ "$r" != 200 ]; then echo "Request $i -> $r"; grep -i 'ratelimit\|retry-after\|x-served\|x-ak' /tmp/h; head -c 300 /tmp/b; echo; break; fi
done
[ "$r" = 200 ] && echo "130 Downloads ohne Fehler"
grep -i ratelimit /tmp/h
