#!/usr/bin/env bash
J=/tmp/rt-cookies; U=http://localhost:8082/ui/api/v1; H=(-b $J -H 'X-Requested-With: XMLHttpRequest')
for p in "ui/admin/repositories/example-repo-local" "ui/admin/repositories/defaultvalues" \
         "ui/admin/repositories/availablechoices" "access/api/ui/users" "access/api/ui/groups" \
         "ui/users" "ui/groups" "access/api/ui/permissions"; do
  echo "== GET $p -> $(curl -s -o /tmp/out.json -w '%{http_code}' "${H[@]}" "$U/$p")"
  head -c 700 /tmp/out.json; echo
done
