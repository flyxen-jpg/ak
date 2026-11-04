#!/usr/bin/env bash
# Einmalig auf rocky10: Garage-Knoten verbinden, Layout (3 Zonen) anwenden, Bucket + Key anlegen.
# Ergebnis: ~/ha/s3.env (S3_ACCESS_KEY_ID / S3_SECRET_ACCESS_KEY) zum Verteilen auf die AK-Knoten.
# Aufruf: 21-garage-layout.sh <node-id-1@ip:3901> <node-id-2@ip:3901>
set -euo pipefail
cd "$(dirname "$0")"; source ./lab.conf
g() { podman exec garage /garage "$@"; }
for peer in "$@"; do g node connect "$peer"; done
sleep 3
i=0
for id in $(g status 2>/dev/null | awk '/^[0-9a-f]{16}/{print $1}'); do
  i=$((i+1)); g layout assign -z "dc$i" -c 20G "$id" >/dev/null
done
g layout apply --version 1
sleep 2
g status
g bucket create "$S3_BUCKET" || true
g key create ak-backend >/dev/null 2>&1 || true
g bucket allow --read --write --owner "$S3_BUCKET" --key ak-backend
KEYINFO=$(g key info ak-backend --show-secret)
KID=$(echo "$KEYINFO" | awk -F': *' '/Key ID/{print $2; exit}')
KSEC=$(echo "$KEYINFO" | awk -F': *' '/Secret key/{print $2; exit}')
printf 'S3_ACCESS_KEY_ID=%s\nS3_SECRET_ACCESS_KEY=%s\n' "$KID" "$KSEC" > ~/ha/s3.env
chmod 600 ~/ha/s3.env
echo "Bucket '$S3_BUCKET' + Key ak-backend ($KID) angelegt -> ~/ha/s3.env"
