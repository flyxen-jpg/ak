#!/usr/bin/env bash
# PostgreSQL 18 + Patroni (PGDG-Pakete, systemd) auf ak-node1/ak-node2.
# DCS = etcd-Cluster (3 Stimmen inkl. rocky10) -> automatischer Failover ohne Split-Brain.
# Aufruf: 40-patroni.sh <name> <ip>
set -euo pipefail
NAME=$1; IP=$2
cd "$(dirname "$0")"; source ./lab.conf; source ./secrets.env
DATA=/var/lib/pgsql/$PG_MAJOR/data
BIN=/usr/pgsql-$PG_MAJOR/bin

# TLS-Zertifikat fuer PostgreSQL (selbstsigniert, Lab)
sudo install -d -o postgres -g postgres -m 700 /var/lib/pgsql/ssl
if ! sudo test -f /var/lib/pgsql/ssl/server.crt; then
  sudo -u postgres openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout /var/lib/pgsql/ssl/server.key -out /var/lib/pgsql/ssl/server.crt \
    -subj "/CN=$NAME.lab.local" -addext "subjectAltName=DNS:$NAME.lab.local,IP:$IP,IP:$VIP"
  sudo chmod 600 /var/lib/pgsql/ssl/server.key
fi

# post_bootstrap: legt nach dem allerersten initdb die AK-Rolle + DB an (laeuft nur auf dem ersten Leader)
sudo install -d -o postgres -g postgres -m 750 /etc/patroni
sudo tee /etc/patroni/post_bootstrap.sh >/dev/null <<EOF
#!/bin/bash
psql "\$1" -v ON_ERROR_STOP=1 <<SQL
CREATE ROLE registry LOGIN PASSWORD '$PG_REGISTRY_PASSWORD';
CREATE DATABASE artifact_registry OWNER registry;
SQL
EOF
sudo chown postgres:postgres /etc/patroni/post_bootstrap.sh; sudo chmod 700 /etc/patroni/post_bootstrap.sh

sudo tee /etc/patroni/patroni.yml >/dev/null <<EOF
scope: ak-pg
namespace: /db/
name: $NAME

restapi:
  listen: 0.0.0.0:8008
  connect_address: $IP:8008

etcd3:
  hosts: $IP_INFRA:2379,$IP_NODE1:2379,$IP_NODE2:2379

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        max_connections: 200
        wal_level: replica
        hot_standby: "on"
        max_wal_senders: 10
        max_replication_slots: 10
        wal_keep_size: 256MB
        wal_log_hints: "on"
        password_encryption: scram-sha-256
        shared_buffers: 128MB
        ssl: "on"
        ssl_cert_file: /var/lib/pgsql/ssl/server.crt
        ssl_key_file: /var/lib/pgsql/ssl/server.key
  initdb:
    - encoding: UTF8
    - data-checksums
  post_bootstrap: /etc/patroni/post_bootstrap.sh

postgresql:
  listen: 0.0.0.0:5432
  connect_address: $IP:5432
  data_dir: $DATA
  bin_dir: $BIN
  pgpass: /var/lib/pgsql/.pgpass_patroni
  authentication:
    superuser:
      username: postgres
      password: '$PG_SUPERUSER_PASSWORD'
    replication:
      username: replicator
      password: '$PG_REPLICATION_PASSWORD'
    rewind:
      username: postgres
      password: '$PG_SUPERUSER_PASSWORD'
  pg_hba:
    - local all all peer
    - hostssl replication replicator $LAB_NET scram-sha-256
    - host replication replicator 127.0.0.1/32 scram-sha-256
    - hostssl all all $LAB_NET scram-sha-256
    - host all all 127.0.0.1/32 scram-sha-256

tags:
  nofailover: false
  noloadbalance: false
  clonefrom: false
  nosync: false
EOF
sudo chown postgres:postgres /etc/patroni/patroni.yml; sudo chmod 600 /etc/patroni/patroni.yml

UNIT=$(systemctl list-unit-files 'patroni*.service' --no-legend | awk '{print $1}' | head -1)
echo "Patroni-Unit: ${UNIT:-?}  Config-Pfad laut Unit: $(systemctl cat "$UNIT" 2>/dev/null | grep -o '/etc/patroni[^ ]*' | head -1)"
sudo systemctl enable --now "$UNIT"
sleep 8
sudo -u postgres patronictl -c /etc/patroni/patroni.yml list || true
