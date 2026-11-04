#!/usr/bin/env bash
source ~/ha/lab.conf; source ~/ha/secrets.env
for p in maven-releases/com/example/core/maven-metadata.xml maven-snapshots/com/example/core/3.0.0-SNAPSHOT/maven-metadata.xml; do
  echo "== $p"
  diff <(curl -s -u admin:password "http://localhost:8082/artifactory/$p") \
       <(curl -s -u "admin:$ADMIN_PASSWORD" "http://$VIP/maven/$p") | head -30
done
