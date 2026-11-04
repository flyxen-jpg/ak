#!/usr/bin/env bash
# Erzeugt .env mit zufaelligen Secrets (nur falls noch nicht vorhanden) und startet den Stack.
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -f .env ]]; then
  cp .env.example .env
  rnd() { openssl rand -base64 "$1" | tr -d '\n/+=' ; }
  sed -i \
    -e "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(rnd 24)|" \
    -e "s|^JWT_SECRET=.*|JWT_SECRET=$(openssl rand -base64 48 | tr -d '\n')|" \
    -e "s|^AK_WEBHOOK_SECRET_KEY=.*|AK_WEBHOOK_SECRET_KEY=$(openssl rand -base64 32 | tr -d '\n')|" \
    -e "s|^ADMIN_PASSWORD=.*|ADMIN_PASSWORD=Ak-$(rnd 18)!|" \
    -e "s|^DEPENDENCY_TRACK_ADMIN_PASSWORD=.*|DEPENDENCY_TRACK_ADMIN_PASSWORD=Dt-$(rnd 18)!|" \
    .env
  chmod 600 .env
  echo ".env erzeugt (Admin-Passwort: grep ADMIN_PASSWORD .env)"
fi

# Postgres-TLS-Zertifikate (ersetzt den pg-certs-Init-Container des Originals)
if [[ ! -f docker/certs/server.crt ]]; then
  mkdir -p docker/certs && cd docker/certs
  openssl genrsa -out ca.key 4096 2>/dev/null
  openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 -out ca.crt \
    -subj "/CN=Artifact Keeper CA/O=Artifact Keeper/C=DE"
  openssl genrsa -out server.key 2048 2>/dev/null
  openssl req -new -key server.key -out server.csr -subj "/CN=postgres/O=Artifact Keeper/C=DE"
  printf '%s\n' "basicConstraints=CA:FALSE" \
    "keyUsage=digitalSignature,nonRepudiation,keyEncipherment,dataEncipherment" \
    "subjectAltName=DNS:localhost,DNS:postgres,IP:127.0.0.1" > server.ext
  openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
    -out server.crt -days 3650 -sha256 -extfile server.ext 2>/dev/null
  rm -f server.csr server.ext ca.srl
  chmod 600 server.key ca.key
  chmod 644 server.crt ca.crt
  # uid/gid 70 = postgres im Alpine-Image, abgebildet im rootless User-Namespace
  podman unshare chown 70:70 server.key server.crt ca.crt
  cd ../..
  echo "Postgres-Zertifikate erzeugt"
fi

podman compose up -d
