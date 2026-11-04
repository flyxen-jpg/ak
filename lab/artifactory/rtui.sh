#!/usr/bin/env bash
# Hilfsfunktionen fuer die interne UI-API von Artifactory OSS (REST-Admin-APIs sind dort "Pro only").
# Nutzung: source rtui.sh; rt_login; rt_post <pfad> <json>
RT_UI=${RT_UI:-http://localhost:8082/ui/api/v1}
RT_USER=${RT_USER:-admin}
RT_PASS=${RT_PASS:-password}
RT_JAR=/tmp/rt-ui-cookies

rt_login() {
  rm -f "$RT_JAR"
  curl -s --max-time 60 --retry 2 -c "$RT_JAR" -b "$RT_JAR" -o /dev/null -w '%{http_code}' -X POST \
    "$RT_UI/ui/auth/login?_spring_security_remember_me=false" \
    -H 'Content-Type: application/json' -H 'X-Requested-With: XMLHttpRequest' \
    -d "{\"user\":\"$RT_USER\",\"password\":\"$RT_PASS\",\"type\":\"login\"}"
}
rt_get()  { curl -s -b "$RT_JAR" -H 'X-Requested-With: XMLHttpRequest' "$RT_UI/$1"; }
rt_send() { # <METHOD> <pfad> <json>
  curl -s -b "$RT_JAR" -w '\nHTTP %{http_code}\n' -X "$1" -H 'X-Requested-With: XMLHttpRequest' \
    -H 'Content-Type: application/json' "$RT_UI/$2" -d "$3"
}
