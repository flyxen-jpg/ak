#!/usr/bin/env bash
# OpenSearch-Knoten (3er-Cluster, Security-Plugin aus wie im AK-Compose).  Aufruf: 30-opensearch.sh <name> <ip>
set -euo pipefail
NAME=$1; IP=$2
cd "$(dirname "$0")"; source ./lab.conf
podman rm -f opensearch >/dev/null 2>&1 || true
podman volume create opensearch-data >/dev/null 2>&1 || true
podman run -d --name opensearch --network host --restart always \
  --ulimit nofile=65536:65536 \
  -e cluster.name=ak-search -e node.name="$NAME" \
  -e network.bind_host=0.0.0.0 -e network.publish_host="$IP" \
  -e discovery.seed_hosts="$IP_INFRA,$IP_NODE1,$IP_NODE2" \
  -e cluster.initial_cluster_manager_nodes="rocky10,ak-node1,ak-node2" \
  -e OPENSEARCH_JAVA_OPTS="-Xms256m -Xmx256m" \
  -e DISABLE_SECURITY_PLUGIN=true -e DISABLE_INSTALL_DEMO_CONFIG=true \
  -v opensearch-data:/usr/share/opensearch/data \
  "$OPENSEARCH_IMAGE" >/dev/null
echo "opensearch auf $NAME gestartet"
