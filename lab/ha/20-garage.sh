#!/usr/bin/env bash
# Garage-S3-Knoten (3 Stueck, replication_factor=3) als rootless Podman-Container im Host-Netz.
# Ersetzt MinIO (keine Community-Images mehr seit 2025).   Aufruf: 20-garage.sh <ip>
set -euo pipefail
IP=$1
cd "$(dirname "$0")"; source ./lab.conf; source ./secrets.env
mkdir -p ~/ha-data
cat > ~/ha-data/garage.toml <<EOF
metadata_dir = "/var/lib/garage/meta"
data_dir = "/var/lib/garage/data"
db_engine = "lmdb"
replication_factor = 3
consistency_mode = "consistent"
rpc_bind_addr = "0.0.0.0:3901"
rpc_public_addr = "$IP:3901"
rpc_secret = "$GARAGE_RPC_SECRET"

[s3_api]
s3_region = "garage"
api_bind_addr = "0.0.0.0:3900"
root_domain = ".s3.lab.local"

[admin]
api_bind_addr = "0.0.0.0:3903"
admin_token = "$GARAGE_ADMIN_TOKEN"
metrics_token = "$GARAGE_ADMIN_TOKEN"
EOF
chmod 600 ~/ha-data/garage.toml
podman rm -f garage >/dev/null 2>&1 || true
podman volume create garage-meta >/dev/null 2>&1 || true
podman volume create garage-data >/dev/null 2>&1 || true
podman run -d --name garage --network host --restart always \
  -v "$HOME/ha-data/garage.toml:/etc/garage.toml:ro,Z" \
  -v garage-meta:/var/lib/garage/meta -v garage-data:/var/lib/garage/data \
  "$GARAGE_IMAGE" >/dev/null
sleep 3
echo "garage auf $(hostname -s): $(podman exec garage /garage node id -q 2>/dev/null)"
