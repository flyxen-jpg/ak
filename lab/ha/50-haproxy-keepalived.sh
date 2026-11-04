#!/usr/bin/env bash
# HAProxy + keepalived (VRRP, unicast) auf ak-node1/ak-node2.
# Beide Knoten starten als BACKUP mit nopreempt: die VIP bleibt nach einem Failover beim
# neuen Halter (kein zweiter Umschaltvorgang, wenn der alte Knoten zurueckkommt).
# Aufruf: 50-haproxy-keepalived.sh <name> <ip> <peer-ip> <prioritaet>
set -euo pipefail
NAME=$1; IP=$2; PEER=$3; PRIO=$4
cd "$(dirname "$0")"; source ./lab.conf; source ./secrets.env

# Pre-Flight: die VIP darf von niemand anderem beantwortet werden (Duplicate Address Detection).
# Ausnahme: der Peer haelt sie bereits (erneuter Lauf auf dem zweiten Knoten).
if ! ip -4 -o addr show "$LAB_IF" | grep -q " $VIP/"; then
  owner=$( (sudo arping -c 2 -w 3 -I "$LAB_IF" "$VIP" 2>/dev/null || true) | grep -o '\[[0-9A-Fa-f:]*\]' | head -1 | tr -d '[]' || true)
  peer_mac=$(ip neigh show "$PEER" | awk '{print $5}')
  echo "Pre-Flight VIP $VIP: ${owner:-frei}"
  if [ -n "$owner" ] && [ "${owner,,}" != "${peer_mac,,}" ]; then
    echo "ABBRUCH: VIP $VIP wird bereits von MAC $owner beantwortet (IP-Konflikt)." >&2; exit 1
  fi
fi

sed -e "s/@IP_INFRA@/$IP_INFRA/g" -e "s/@IP_NODE1@/$IP_NODE1/g" -e "s/@IP_NODE2@/$IP_NODE2/g" \
  haproxy.cfg.tpl | sudo tee /etc/haproxy/haproxy.cfg >/dev/null
sudo haproxy -c -q -f /etc/haproxy/haproxy.cfg && echo "haproxy.cfg ok"
sudo systemctl enable --now haproxy
sudo systemctl reload haproxy

sudo tee /etc/keepalived/keepalived.conf >/dev/null <<EOF
global_defs {
    router_id $NAME
    enable_script_security
    script_user root
    vrrp_garp_master_refresh 30
}

# VIP nur halten, solange der lokale HAProxy-Prozess laeuft
vrrp_track_process track_haproxy {
    process haproxy
    weight -50
    delay 1
}

vrrp_instance VI_AK {
    state BACKUP
    nopreempt
    interface $LAB_IF
    virtual_router_id 56
    priority $PRIO
    advert_int 1
    unicast_src_ip $IP
    unicast_peer {
        $PEER
    }
    authentication {
        auth_type PASS
        auth_pass $KEEPALIVED_AUTH_PASS
    }
    virtual_ipaddress {
        $VIP/24 dev $LAB_IF label $LAB_IF:vip
    }
    track_process {
        track_haproxy
    }
}
EOF
sudo chmod 600 /etc/keepalived/keepalived.conf
sudo systemctl enable --now keepalived
sudo systemctl restart keepalived
sleep 4
echo "$NAME: VIP $(ip -4 -o addr show $LAB_IF | grep -q "$VIP" && echo HIER || echo nicht hier)"
