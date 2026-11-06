#!/bin/bash
# Shows what JFrog tries to reach from an isolated network. Without a route a program fails
# before any packet exists, so a gateway is set for the time of the test, before JFrog starts.
# Name servers left in /etc/resolv.conf then make name lookups visible too, and the outbound
# rule of the role restricted_host stops and logs every attempt.
#   tools/evidence/jfrog-outbound.sh [gateway] [minutes]
set -uo pipefail
cd /
gateway=${1:-192.168.56.1}
minutes=${2:-6}
uid=$(id -u ak)
as_ak() { sudo -u ak XDG_RUNTIME_DIR="/run/user/$uid" "$@"; }
counter() { sudo nft list chain inet ak_egress output | sed -n 's/.*counter packets \([0-9]*\).*/\1/p'; }

# All containers of the network must stop: they share one network namespace, which keeps the
# routes of its start as long as one of them runs.
as_ak systemctl --user stop artifactory.service artifactory-postgres.service
sudo ip route add default via "$gateway"
trap 'sudo ip route del default via "$gateway"' EXIT
since=$(date '+%Y-%m-%d %H:%M:%S')
before=$(counter)
as_ak systemctl --user start artifactory-postgres.service
as_ak systemctl --user start --no-block artifactory.service
sleep $((minutes*60))
after=$(counter)
echo "blocked packets while JFrog ran for $minutes minutes: $((after-before))"
echo "destinations (count, address, protocol, port):"
sudo journalctl -k --since "$since" -g ak-egress-drop --no-pager -o cat \
  | sed -nE 's/.*DST=([0-9.]+).*PROTO=([A-Z0-9]+).*DPT=([0-9]+).*/\1 \2 \3/p' | sort | uniq -c | sort -rn | head -20
# Counter check: the rule must see an attempt made from inside the container.
as_ak podman exec artifactory curl -s -m 5 -o /dev/null http://1.1.1.1/
echo "counter check from inside the container: curl exit $?, packets $(( $(counter)-after ))"
echo "health: $(curl -s -m 5 -o /dev/null -w '%{http_code}' http://127.0.0.1:8082/router/api/v1/system/health), REST API: $(curl -s -m 5 http://127.0.0.1:8082/artifactory/api/system/ping)"
