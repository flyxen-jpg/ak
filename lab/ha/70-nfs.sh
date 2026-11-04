#!/usr/bin/env bash
# NFS-Variante fuer den gemeinsamen Artefakt-Speicher (Vergleich zu S3).
#   server: rocky10 exportiert /srv/ak-nfs an das Lab-Netz
#   client: ak-node* mounten nach /srv/ak-nfs (gleicher Pfad auf allen Knoten)
# Rootless Podman: der Container-User 1001 wird auf eine Host-Sub-UID abgebildet. Damit beide
# Knoten dieselbe UID auf dem NFS sehen, squasht der Server alle Zugriffe auf diese eine UID.
# Aufruf: 70-nfs.sh server <anon-uid> | 70-nfs.sh client
set -euo pipefail
cd "$(dirname "$0")"; source ./lab.conf
case "$1" in
  server)
    ANON=$2
    sudo mkdir -p /srv/ak-nfs && sudo chown "$ANON:$ANON" /srv/ak-nfs && sudo chmod 0770 /srv/ak-nfs
    echo "/srv/ak-nfs $LAB_NET(rw,sync,no_subtree_check,all_squash,anonuid=$ANON,anongid=$ANON)" | sudo tee /etc/exports.d/ak.exports >/dev/null
    sudo systemctl enable --now nfs-server >/dev/null 2>&1
    sudo exportfs -ra && sudo exportfs -v | grep ak-nfs ;;
  client)
    sudo mkdir -p /srv/ak-nfs
    grep -q ak-nfs /etc/fstab || echo "$IP_INFRA:/srv/ak-nfs /srv/ak-nfs nfs4 rw,hard,timeo=50,retrans=3,_netdev 0 0" | sudo tee -a /etc/fstab >/dev/null
    sudo systemctl daemon-reload; sudo mount /srv/ak-nfs 2>/dev/null || true
    findmnt /srv/ak-nfs -o TARGET,SOURCE,FSTYPE,OPTIONS | tail -1 ;;
esac
