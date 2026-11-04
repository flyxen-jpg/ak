#!/usr/bin/env bash
# Copies the SSH key of the management node to every host of an inventory, so Ansible can
# log in without password. Asks once per host for the password of the installation account.
#   tools/copy-ssh-keys.sh inventories/natnetwork/hosts.yml [user]
# Only ssh-keygen and ssh-copy-id are used (part of the minimal installation).
set -euo pipefail
INV=${1:?usage: $0 <inventory> [user]}
USER_NAME=${2:-$(id -un)}

[ -f ~/.ssh/id_ed25519 ] || ssh-keygen -q -t ed25519 -N '' -f ~/.ssh/id_ed25519

# Address of every host as Ansible sees it (ansible_host, else the inventory name).
mapfile -t HOSTS < <(ansible-inventory -i "$INV" --list | python3 -c '
import json, sys
d = json.load(sys.stdin)
hv = d.get("_meta", {}).get("hostvars", {})
for h in sorted(set(hv) | set(d.get("all", {}).get("hosts", []))):
    if h != "localhost":
        print(hv.get(h, {}).get("ansible_host", h))')

for h in "${HOSTS[@]}"; do
  echo "==> $h"
  ssh-copy-id -o StrictHostKeyChecking=accept-new "$USER_NAME@$h"
done
