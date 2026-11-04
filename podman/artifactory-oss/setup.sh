#!/usr/bin/env bash
# Erzeugt .env mit zufaelligem DB-Passwort (nur falls noch nicht vorhanden) und startet den Stack.
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -f .env ]]; then
  cp .env.example .env
  sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(openssl rand -base64 24 | tr -d '\n/+=')|" .env
  chmod 600 .env
  echo ".env erzeugt"
fi

podman compose up -d
