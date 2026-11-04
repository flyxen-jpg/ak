#!/usr/bin/env bash
# Statische Host-Only-IP + /etc/hosts fuer das Lab.  Aufruf: net.sh <ip> <hostname>
set -e
IP=$1; NAME=$2
IF=$(ip -o link | awk -F': ' '$2!="lo"{print $2}' | sed -n 2p)
sudo nmcli -t con delete hostonly >/dev/null 2>&1 || true
sudo nmcli con add type ethernet ifname "$IF" con-name hostonly ipv4.method manual ipv4.addresses "$IP/24" ipv6.method disabled >/dev/null
sudo nmcli con up hostonly >/dev/null
sudo hostnamectl set-hostname "$NAME.lab.local"
grep -q lab.local /etc/hosts || printf '%s\n' \
  '192.168.56.10  rocky10.lab.local rocky10' \
  '192.168.56.11  ak-node1.lab.local ak-node1' \
  '192.168.56.12  ak-node2.lab.local ak-node2' \
  '192.168.56.50  ak.lab.local ak' | sudo tee -a /etc/hosts >/dev/null
echo "$(hostname): $(ip -4 -o addr show "$IF" | awk '{print $2, $4}')"
