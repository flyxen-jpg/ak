#!/bin/bash
# Checks of an isolated setup, run from the project directory on the control VM after
# playbooks/airgap.yml. Prints one line per check, PASS or FAIL, plus the evidence.
#   tools/evidence/airgap-check.sh <inventory directory> <other VM address>
# Temporarily adds a default route on both VMs and removes it again.
set -uo pipefail
inv=${1:?inventory directory}
other=${2:?address of the other VM}
gateway=${AIRGAP_TEST_GATEWAY:-192.168.56.1}
fails=0
result() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fails=$((fails+1)); fi; [ -n "${3:-}" ] && echo "     $3"; return 0; }
on_other() { ssh -n -o BatchMode=yes "$other" "$@"; }

echo "=== 1. Network"
for target in local other; do
  run() { if [ "$target" = local ]; then bash -c "$1"; else on_other "$1"; fi; }
  route=$(run 'ip route show default')
  result "$target has no default route" "$([ -z "$route" ]; echo $?)" "$route"
  run 'timeout 4 bash -c "</dev/tcp/1.1.1.1/443"' 2>/dev/null
  result "$target cannot reach 1.1.1.1" "$([ $? -ne 0 ]; echo $?)"
  run 'getent hosts ghcr.io' >/dev/null 2>&1
  result "$target cannot resolve ghcr.io" "$([ $? -ne 0 ]; echo $?)"
done

echo "=== 2. Outbound rules also hold when a gateway appears"
for target in local other; do
  run() { if [ "$target" = local ]; then bash -c "$1"; else on_other "$1"; fi; }
  before=$(run 'sudo nft list chain inet ak_egress output' | sed -n 's/.*counter packets \([0-9]*\).*/\1/p')
  run "sudo ip route add default via $gateway"
  run 'timeout 3 bash -c "</dev/tcp/1.1.1.1/443"' 2>/dev/null
  host_blocked=$?
  middle=$(run 'sudo nft list chain inet ak_egress output' | sed -n 's/.*counter packets \([0-9]*\).*/\1/p')
  # A container leaves through processes of the host when it runs rootless.
  run 'cd /; c=$(sudo -u ak XDG_RUNTIME_DIR=/run/user/$(id -u ak) podman ps --format "{{.Names}}" | grep -E "^(artifactory|ak-backend)$" | head -1); [ -n "$c" ] && sudo -u ak XDG_RUNTIME_DIR=/run/user/$(id -u ak) podman exec "$c" curl -s -m 4 -o /dev/null http://1.1.1.1/' 2>/dev/null
  container_rc=$?
  run "sudo ip route del default via $gateway"
  after=$(run 'sudo nft list chain inet ak_egress output' | sed -n 's/.*counter packets \([0-9]*\).*/\1/p')
  result "$target blocks the host" "$([ "$host_blocked" -ne 0 ]; echo $?)"
  result "$target containers do not reach the outside" "$([ "$container_rc" -ne 0 ]; echo $?)" "curl exit code $container_rc, packets stopped by the rule from the container: $((after-middle))"
  result "$target counts the packets blocked for the host" "$([ "$middle" -gt "$before" ]; echo $?)" "counter $before -> $middle"
done
sudo journalctl -k -g ak-egress-drop -n 2 --no-pager -o cat 2>/dev/null | cut -c1-140 | sed 's/^/     /'

echo "=== 3. Hardening"
for target in local other; do
  run() { if [ "$target" = local ]; then bash -c "$1"; else on_other "$1"; fi; }
  run 'cp /usr/bin/true /tmp/airgap-x && /tmp/airgap-x' 2>/dev/null
  result "$target refuses to run files from /tmp" "$([ $? -ne 0 ]; echo $?)"
  run 'rm -f /tmp/airgap-x; cp /usr/bin/true /var/tmp/airgap-x && /var/tmp/airgap-x' 2>/dev/null
  result "$target refuses to run files from /var/tmp" "$([ $? -ne 0 ]; echo $?)"
  run 'rm -f /var/tmp/airgap-x'
  mode=$(run 'getenforce')
  result "$target SELinux enforcing" "$([ "$mode" = Enforcing ]; echo $?)" "$mode"
  avc=$(run 'sudo journalctl -b -k -g "avc:  denied" --no-pager -q 2>/dev/null | wc -l')
  result "$target has no SELinux denials since boot" "$([ "$avc" = 0 ]; echo $?)" "$avc denials"
  gpg=$(run 'grep -h "^gpgcheck" /etc/yum.repos.d/ak-offline.repo')
  result "$target verifies package signatures" "$([ "$gpg" = "gpgcheck = 1" ] || [ "$gpg" = "gpgcheck=1" ]; echo $?)" "$gpg"
  enabled=$(run 'dnf -q repolist --enabled 2>/dev/null | tail -n +2 | wc -l')
  result "$target knows only the bundle repository" "$([ "$enabled" = 1 ]; echo $?)" "$enabled enabled"
done

echo "=== 4. Time"
chrony=$(on_other 'chronyc -n sources' | tail -1)
case "$chrony" in '^*'*) rc=0 ;; *) rc=1 ;; esac
result "other VM follows the local time server" "$rc" "$chrony"

echo "=== 5. Bundle"
touch /srv/ak-bundle/write-test 2>/dev/null
result "bundle is mounted read only" "$([ $? -ne 0 ]; echo $?)"
(cd /srv/ak-bundle && sha256sum --quiet -c SHA256SUMS >/dev/null 2>&1)
result "bundle checksums are correct" "$?"
tampered=$(mktemp -d -p ~)
cp /srv/ak-bundle/BUNDLE_ID "$tampered/"
grep ' \./BUNDLE_ID$' /srv/ak-bundle/SHA256SUMS > "$tampered/SHA256SUMS"
echo changed >> "$tampered/BUNDLE_ID"
(cd "$tampered" && sha256sum --quiet -c SHA256SUMS >/dev/null 2>&1)
result "a changed file is detected" "$([ $? -ne 0 ]; echo $?)"
rm -rf "$tampered"

echo "=== 6. Play stops when a host is not isolated"
output=$(ansible-playbook -i "$inv/hosts.yml" playbooks/airgap.yml --tags restricted_host --limit "$(hostname -s)" \
  -e '{"restricted_host_probe_names":["localhost"]}' 2>&1)
echo "$output" | grep -q 'Host reaches the outside'
result "play refuses a host that reaches the outside" "$?" "$(echo "$output" | grep -o 'Host reaches the outside[^.]*' | head -1)"

echo "=== Summary: $fails failed"
exit "$fails"
