#!/usr/bin/env bash
# haengende dnf-Laeufe beenden (nur den Python-Prozess, nicht sudo/ssh-Eltern)
for p in $(pgrep -f '^/usr/bin/python3 .*/usr/bin/dnf'); do sudo kill "$p"; done; sleep 1
grep -q '^timeout=' /etc/dnf/dnf.conf || printf 'timeout=20\nminrate=50k\n' | sudo tee -a /etc/dnf/dnf.conf >/dev/null
sudo dnf -y -q install epel-release >/dev/null 2>&1
sudo dnf -y -q install https://download.postgresql.org/pub/repos/yum/reporpms/EL-10-x86_64/pgdg-redhat-repo-latest.noarch.rpm >/dev/null 2>&1
sudo dnf -y -q makecache >/dev/null 2>&1   # importiert GPG-Keys nicht-interaktiv
for p in haproxy keepalived patroni patroni-etcd etcd postgresql-server postgresql17-server postgresql18-server nfs-utils; do
  v=$(dnf -y -q repoquery --latest-limit 1 --qf '%{version}-%{release} [%{repoid}]' "$p" 2>/dev/null | head -1)
  printf '%-22s %s\n' "$p" "${v:-NICHT VERFUEGBAR}"
done
free -h | head -2
