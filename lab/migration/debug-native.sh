#!/usr/bin/env bash
source ~/ha/lab.conf; source ~/ha/secrets.env; AK=http://$VIP
sleep 61   # Rate-Limit-Fenster abwarten
A=(-u "admin:$ADMIN_PASSWORD")
for u in "/generic/generic-files/releases/batch-1/file-60.bin" "/general/generic-files/releases/batch-1/file-60.bin" \
         "/maven/maven-releases/com/example/core/1.0.0/core-1.0.0.pom" "/maven/maven-all/junit/junit/4.13.2/junit-4.13.2.pom" \
         "/maven/maven-central/junit/junit/4.13.2/junit-4.13.2.pom"; do
  printf '%-62s %s\n' "$u" "$(curl -s -o /dev/null -D /tmp/h -w '%{http_code}' "${A[@]}" "$AK$u") $(grep -i 'x-ratelimit-limit' /tmp/h | tr -d '\r')"
done
echo "== 200 Downloads ueber den nativen Maven-Endpunkt"
ok=0; for i in $(seq 1 200); do c=$(curl -s -o /dev/null -w '%{http_code}' "${A[@]}" "$AK/maven/maven-releases/com/example/core/1.0.0/core-1.0.0.pom"); [ "$c" = 200 ] && ok=$((ok+1)); done
echo "   $ok/200 OK  (Limit-Header: $(curl -s -o /dev/null -D - "${A[@]}" "$AK/maven/maven-releases/com/example/core/1.0.0/core-1.0.0.pom" | grep -i 'x-ratelimit-limit' | tr -d '\r'))"
