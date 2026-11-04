#!/usr/bin/env bash
# etcd-Mitglied (3 Stueck: rocky10, ak-node1, ak-node2) als rootless Podman-Container im Host-Netz.
# etcd ist der DCS (Distributed Configuration Store) fuer Patroni: Leader-Wahl + Cluster-Zustand.
# Aufruf: 10-etcd.sh <name> <ip>
set -euo pipefail
NAME=$1; IP=$2
cd "$(dirname "$0")"; source ./lab.conf
CLUSTER="rocky10=http://$IP_INFRA:2380,ak-node1=http://$IP_NODE1:2380,ak-node2=http://$IP_NODE2:2380"
podman rm -f etcd >/dev/null 2>&1 || true
podman volume create etcd-data >/dev/null 2>&1 || true
podman run -d --name etcd --network host --restart always \
  -v etcd-data:/etcd-data \
  "$ETCD_IMAGE" /usr/local/bin/etcd \
    --name "$NAME" --data-dir /etcd-data \
    --listen-client-urls "http://$IP:2379,http://127.0.0.1:2379" \
    --advertise-client-urls "http://$IP:2379" \
    --listen-peer-urls "http://$IP:2380" \
    --initial-advertise-peer-urls "http://$IP:2380" \
    --initial-cluster "$CLUSTER" --initial-cluster-state new --initial-cluster-token ak-lab-etcd \
    --heartbeat-interval 250 --election-timeout 2500 >/dev/null
echo "etcd auf $NAME gestartet"
