#!/usr/bin/env bash
# Verhalten der AK-Knoten waehrend der NFS-Server weg ist (von innerhalb des Labornetzes)
source ~/ha/secrets.env
A=(-u "admin:$ADMIN_PASSWORD")
for i in 1 2 3; do curl -s -m 15 -o /dev/null -w "GET  nfs-5mb.bin  -> %{http_code} nach %{time_total}s\n" "${A[@]}" http://192.168.56.50/general/nfs-generic/test/nfs-5mb.bin; done
echo x > /tmp/x
curl -s -m 15 -o /dev/null -w "PUT  x.bin        -> %{http_code} nach %{time_total}s\n" "${A[@]}" -T /tmp/x http://192.168.56.50/api/v1/repositories/nfs-generic/artifacts/test/x.bin
curl -s -m 5 -o /dev/null -w "GET  /readyz      -> %{http_code} nach %{time_total}s\n" http://192.168.56.50/readyz
echo "haengende Prozesse im D-State auf $(hostname -s): $(ps -eo stat,comm | awk '$1 ~ /^D/' | wc -l)"
