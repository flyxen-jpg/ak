#!/usr/bin/env bash
# rocky10: statische Host-Only-IP + /etc/hosts fuer das Lab
set -e
IF=$(ip -o link | awk -F': ' '$2!="lo"{print $2}' | sed -n 2p)
sudo nmcli -t con delete hostonly >/dev/null 2>&1 || true
sudo nmcli con add type ethernet ifname "$IF" con-name hostonly ipv4.method manual ipv4.addresses 192.168.56.10/24 ipv6.method disabled >/dev/null
sudo nmcli con up hostonly >/dev/null
sudo hostnamectl set-hostname rocky10.lab.local
grep -q lab.local /etc/hosts || printf '192.168.56.10 rocky10.lab.local rocky10\n192.168.56.11 ak-node1.lab.local ak-node1\n192.168.56.12 ak-node2.lab.local ak-node2\n192.168.56.100 ak.lab.local ak\n' | sudo tee -a /etc/hosts >/dev/null
ip -4 -o addr show "$IF"
free -h | head -2
podman ps --format '{{.Names}} {{.Status}}'
