#!/bin/bash
# Migration test in the isolated network, run from the project directory on the control VM.
#   tools/evidence/airgap-migration.sh <inventory directory> [log directory]
# Each step is timed and has its own log. A failed step is reported and the next one runs.
set -uo pipefail
inv=${1:?inventory directory}
logs=${2:-$HOME/airgap-logs}
export ANSIBLE_VAULT_PASSWORD_FILE=${ANSIBLE_VAULT_PASSWORD_FILE:-$HOME/.ansible/ak-vault-pass}
mkdir -p "$logs"

step() {
  local name=$1; shift
  local start=$SECONDS
  "$@" > "$logs/$name.log" 2>&1
  local rc=$?
  echo "$name: exit $rc, $((SECONDS-start)) s, $(grep -E 'ok=[0-9]+' "$logs/$name.log" | sed 's/  */ /g' | cut -d' ' -f1,3-6,8 | tr '\n' ';')"
}
play() { ansible-playbook -i "$inv/hosts.yml" "$@"; }

step artifacts play playbooks/migrate.yml --tags artifacts,verify
step images play playbooks/migrate.yml --tags verify_images
step security play playbooks/migrate.yml --tags security
step delta play playbooks/migrate.yml --tags artifacts
grep -hE 'Job (full|incremental)|Items:|Data:|Failed:' "$logs/artifacts.log" "$logs/delta.log" | cut -c1-150
grep -hE 'Compared:|Images:' "$logs/artifacts.log" "$logs/images.log" | cut -c1-150
grep -hE '"?Groups|Users|Rules|rules:|groups:' "$logs/security.log" | cut -c1-150 | tail -8
