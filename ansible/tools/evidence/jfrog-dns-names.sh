#!/bin/bash
# Shows which names JFrog looks up. A small listener on this VM logs every question and answers
# "name not found", so nothing leaves the network. /etc/resolv.conf is restored afterwards.
#   tools/evidence/jfrog-dns-names.sh <address of this VM> [minutes] [gateway]
# Rootless containers only get a network path when a default route exists at their start, so a
# gateway is set for the test. The outbound rule of the role restricted_host still applies.
set -uo pipefail
cd /
address=${1:?address of this VM}
minutes=${2:-6}
gateway=${3:-192.168.56.1}
uid=$(id -u ak)
as_ak() { sudo -u ak XDG_RUNTIME_DIR="/run/user/$uid" "$@"; }
log=/var/tmp/jfrog-dns-names.log

as_ak systemctl --user stop artifactory.service artifactory-postgres.service
sudo cp -p /etc/resolv.conf /etc/resolv.conf.dns-test
listener=$(mktemp -p /var/tmp dns-listener.XXXXXX)
cat > "$listener" <<'EOF'
import socket, sys
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(("0.0.0.0", 53))
with open(sys.argv[1], "a", buffering=1) as log:
    while True:
        data, peer = s.recvfrom(512)
        labels, i = [], 12
        while i < len(data) and data[i]:
            labels.append(data[i + 1:i + 1 + data[i]].decode("ascii", "replace"))
            i += data[i] + 1
        log.write(".".join(labels) + "\n")
        # Same question, response flag and "name not found".
        s.sendto(data[:2] + b"\x81\x83" + data[4:6] + b"\0\0\0\0\0\0" + data[12:i + 5], peer)
EOF
sudo rm -f "$log"
sudo python3 "$listener" "$log" &
sudo sh -c "echo nameserver $address > /etc/resolv.conf"
sudo ip route add default via "$gateway"
trap 'sudo ip route del default via "$gateway"; sudo pkill -f "$listener"; sudo mv -f /etc/resolv.conf.dns-test /etc/resolv.conf; rm -f "$listener"' EXIT
as_ak systemctl --user start artifactory-postgres.service
as_ak systemctl --user start --no-block artifactory.service
sleep $((minutes*60))
# Counter check: a lookup from inside the container must reach the listener.
as_ak podman exec artifactory curl -s -m 5 -o /dev/null http://counter-check.invalid/
echo "questions in $minutes minutes (count, name):"
sudo sort "$log" | uniq -c | sort -rn | head -30
echo "health: $(curl -s -m 5 -o /dev/null -w '%{http_code}' http://127.0.0.1:8082/router/api/v1/system/health)"
