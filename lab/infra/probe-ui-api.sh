#!/usr/bin/env bash
# Prueft, ob die interne UI-API von Artifactory OSS per Session-Cookie nutzbar ist
J=/tmp/rt-cookies; rm -f $J
U=http://localhost:8082/ui/api/v1
curl -s -c $J -b $J -o /dev/null -w "login %{http_code}\n" -X POST "$U/ui/auth/login?_spring_security_remember_me=false" \
  -H 'Content-Type: application/json' -H 'X-Requested-With: XMLHttpRequest' \
  -d '{"user":"admin","password":"password","type":"login"}'
echo "== Repos (UI-API)"
curl -s -b $J -H 'X-Requested-With: XMLHttpRequest' "$U/ui/admin/repositories/local/info" | head -c 400; echo
