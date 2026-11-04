#!/usr/bin/env bash
# Basis fuer alle Lab-VMs.  Aufruf: 00-base.sh infra|node
set -euo pipefail
ROLE=$1
cd "$(dirname "$0")"; source ./lab.conf
step() { printf '\n\033[1;36m[%s] %s\033[0m\n' "$(hostname -s)" "$*"; }

step "Repos + Pakete"
grep -q '^timeout=' /etc/dnf/dnf.conf || printf 'timeout=20\nminrate=50k\n' | sudo tee -a /etc/dnf/dnf.conf >/dev/null
sudo dnf -y -q install epel-release
PKGS="podman podman-compose jq tar curl openssl nfs-utils bind-utils"
if [ "$ROLE" = node ]; then
  rpm -q pgdg-redhat-repo >/dev/null 2>&1 || sudo dnf -y -q install \
    https://download.postgresql.org/pub/repos/yum/reporpms/EL-10-x86_64/pgdg-redhat-repo-latest.noarch.rpm
  sudo dnf -y -q makecache >/dev/null
  PKGS="$PKGS socat haproxy keepalived postgresql${PG_MAJOR}-server postgresql${PG_MAJOR}-contrib patroni patroni-etcd"
fi
sudo dnf -y -q install $PKGS
rpm -q --qf '   %{NAME}-%{VERSION}\n' $PKGS | sort

step "Kernel-Parameter"
sudo tee /etc/sysctl.d/90-lab.conf >/dev/null <<EOF
vm.max_map_count=262144
net.ipv4.ip_nonlocal_bind=1
vm.swappiness=10
EOF
sudo sysctl -q --system

step "Firewall (Zone public, nur Lab-Netz $LAB_NET fuer Clusterdienste)"
sudo firewall-cmd -q --permanent --new-zone=lab 2>/dev/null || true
sudo firewall-cmd -q --permanent --zone=lab --add-source=$LAB_NET
for p in 2379 2380 3900 3901 3903 9200 9300; do sudo firewall-cmd -q --permanent --zone=lab --add-port=$p/tcp; done
if [ "$ROLE" = node ]; then
  for p in 80 3000 3910 5000 5432 8008 8080 8404 9201; do sudo firewall-cmd -q --permanent --zone=lab --add-port=$p/tcp; done
  sudo firewall-cmd -q --permanent --zone=lab --add-rich-rule='rule protocol value="vrrp" accept'
  sudo firewall-cmd -q --permanent --zone=public --add-port=80/tcp
else
  sudo firewall-cmd -q --permanent --zone=lab --add-service=nfs --add-service=mountd --add-service=rpc-bind
  for p in 8081 8082; do sudo firewall-cmd -q --permanent --zone=lab --add-port=$p/tcp; done
fi
sudo firewall-cmd -q --reload
echo "   lab-Zone: $(sudo firewall-cmd --zone=lab --list-ports | wc -w) Ports offen"

step "SELinux-Booleans"
[ "$ROLE" = node ] && sudo setsebool -P haproxy_connect_any 1
sudo setsebool -P virt_use_nfs 1 2>/dev/null || true
getsebool haproxy_connect_any virt_use_nfs 2>/dev/null | sed 's/^/   /'

step "rootless Podman: linger + Autostart"
sudo loginctl enable-linger rocky
systemctl --user enable --now podman-restart.service >/dev/null 2>&1
mkdir -p ~/ha-data
echo "   fertig"
