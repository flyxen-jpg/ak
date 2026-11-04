#!/usr/bin/env bash
# Startet Artifact Keeper auf einem HA-Knoten.  Aufruf: 60-ak-node.sh <ip> [s3|nfs]
set -euo pipefail
IP=$1; STORAGE=${2:-s3}
cd "$(dirname "$0")"; source ./lab.conf; source ./secrets.env
mkdir -p ~/ak && cp ak-node.compose.yaml ~/ak/compose.yaml
AK_WEB_VERSION=${AK_WEB_VERSION:-latest}

{
  echo "# generiert von 60-ak-node.sh ($(date -Is)) - Knoten $IP, Storage $STORAGE"
  echo "AK_VERSION=$AK_VERSION"
  echo "AK_WEB_VERSION=$AK_WEB_VERSION"
  echo "NODE_IP=$IP"
} > ~/ak/.env

{
  echo "HOST=0.0.0.0"
  echo "PORT=8080"
  echo "ENVIRONMENT=production"
  # NFS-Vergleich laeuft auf einer eigenen Datenbank, damit der S3-Bestand unberuehrt bleibt
  DB=artifact_registry; [ "$STORAGE" = nfs ] && DB=artifact_registry_nfs
  echo "DATABASE_URL=postgresql://registry:$PG_REGISTRY_PASSWORD@$IP:5000/$DB?sslmode=require"
  echo "DATABASE_MAX_CONNECTIONS=20"
  echo "DATABASE_MIN_CONNECTIONS=2"
  echo "DATABASE_TCP_KEEPALIVES=true"
  echo "JWT_SECRET=$JWT_SECRET"
  echo "AK_WEBHOOK_SECRET_KEY=$AK_WEBHOOK_SECRET_KEY"
  echo "MIGRATION_ENCRYPTION_KEY=$MIGRATION_ENCRYPTION_KEY"
  echo "SSO_ENCRYPTION_KEY=$SSO_ENCRYPTION_KEY"
  echo "ADMIN_PASSWORD=$ADMIN_PASSWORD"
  echo "AK_EXTERNAL_URL=http://$VIP"
  echo "CORS_ORIGINS=http://$VIP,http://ak.lab.local"
  echo "RATE_LIMIT_TRUSTED_PROXY_CIDRS=$LAB_NET"
  echo "XFF_TRUSTED_FOR_AUTHZ=true"
  echo "OPENSEARCH_URL=http://$IP:9201"
  echo "ALLOW_HTTP_INTEGRATIONS=1"
  echo "AK_SSRF_ALLOW_PRIVATE_CIDRS=$AK_SSRF_ALLOW_PRIVATE_CIDRS"
  echo "PROXY_SINGLEFLIGHT_ADVISORY_LOCKS_ENABLED=true"
  echo "STORAGE_PATH=/data/storage"
  echo "BACKUP_PATH=/data/backups"
  echo "PLUGINS_DIR=/data/plugins"
  echo "RUST_LOG=info"
  echo "LOG_ANSI=false"
  if [ "$STORAGE" = s3 ]; then
    source ./s3.env
    echo "STORAGE_BACKEND=s3"
    echo "S3_BUCKET=$S3_BUCKET"
    echo "S3_REGION=garage"
    echo "S3_ENDPOINT=http://$IP:3910"
    echo "S3_ACCESS_KEY_ID=$S3_ACCESS_KEY_ID"
    echo "S3_SECRET_ACCESS_KEY=$S3_SECRET_ACCESS_KEY"
  else
    echo "STORAGE_BACKEND=filesystem"
  fi
} > ~/ak/ak.env
chmod 600 ~/ak/ak.env ~/ak/.env

cp ak-node.compose.nfs.yaml ~/ak/compose.nfs.yaml
cd ~/ak
F=(-f compose.yaml); [ "$STORAGE" = nfs ] && F+=(-f compose.nfs.yaml)
podman compose "${F[@]}" down >/dev/null 2>&1 || true
podman compose "${F[@]}" up -d 2>&1 | grep -vE '^\s*$|Executing external compose provider' || true
echo "warte auf /readyz ..."
for i in $(seq 1 60); do
  s=$(curl -s -o /dev/null -w '%{http_code}' "http://$IP:8080/readyz" || true)
  [ "$s" = 200 ] && break; sleep 3
done
echo "$(hostname -s): /readyz -> $s"
curl -s "http://$IP:8080/health" | jq -c '{status,version,checks: (.checks|map_values(.status))}' 2>/dev/null || true
