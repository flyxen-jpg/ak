#!/usr/bin/env bash
# Prepares an OFFLINE control node from the bundle: ansible-core (RPM) and the collections.
# Run from the project directory:  tools/install-control-node.sh /srv/ak-bundle
# Prerequisite: Rocky Linux / RHEL 10 with sudo; nothing else.
set -euo pipefail
BUNDLE=${1:?usage: $0 <bundle-dir>}
cd "$(dirname "$0")/.."

echo "==> Verifying bundle checksums"
(cd "$BUNDLE" && sha256sum --quiet -c SHA256SUMS)

if ! command -v ansible-playbook >/dev/null; then
  echo "==> Installing ansible-core from the bundle repository"
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  tar -C "$tmp" -xf "$BUNDLE/rpms.tar"
  # Signatures are checked against the vendor keys shipped in the bundle.
  sudo rpm --import "$BUNDLE"/rpm-gpg/*
  sudo dnf -y --disablerepo='*' --repofrompath="ak-bundle,file://$tmp" \
    --setopt=ak-bundle.gpgcheck=1 install ansible-core
fi

echo "==> Installing collections into ./collections"
ansible-galaxy collection install --offline -p collections "$BUNDLE"/collections/*.tar.gz

ansible --version | head -1
ansible-galaxy collection list -p collections 2>/dev/null | grep -E '^[a-z]' || true
