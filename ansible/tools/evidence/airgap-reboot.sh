#!/bin/bash
# Restarts the other VM and this one's services, then measures until everything answers again
# without any intervention. Run from the control VM.
#   tools/evidence/airgap-reboot.sh <Artifact Keeper address> [JFrog address on this VM: yes|no]
set -uo pipefail
ak=${1:?address of the Artifact Keeper VM}
local_jfrog=${2:-yes}

echo "=== Reboot of the Artifact Keeper VM"
ssh -n -o BatchMode=yes "$ak" 'sudo systemctl reboot' 2>/dev/null
start=$SECONDS
sleep 10
until ssh -n -o BatchMode=yes -o ConnectTimeout=3 "$ak" true 2>/dev/null; do sleep 2; done
echo "ssh back after $((SECONDS-start)) s"
until [ "$(curl -s -m 3 -o /dev/null -w '%{http_code}' "http://$ak:30080/readyz")" = 200 ]; do
  [ $((SECONDS-start)) -gt 600 ] && { echo 'FAIL Artifact Keeper not ready after 600 s'; exit 1; }
  sleep 2
done
echo "Artifact Keeper ready after $((SECONDS-start)) s"
ssh -n -o BatchMode=yes "$ak" 'findmnt -no OPTIONS /tmp | cut -c1-60; findmnt -no OPTIONS /var/tmp | cut -c1-60; sudo nft list chain inet ak_egress output | grep -c "policy drop"; chronyc -n sources | tail -1; ip route show default | wc -l'

if [ "$local_jfrog" = yes ]; then
  echo "=== Reboot of the JFrog VM follows, measured by the helper after boot"
  cat <<'EOF' | sudo tee /usr/local/sbin/air-after-boot.sh >/dev/null
#!/bin/bash
start=$(date +%s)
boot=$(awk '{print int($1)}' /proc/uptime)
until [ "$(curl -s -m 3 http://127.0.0.1:8082/artifactory/api/system/ping)" = OK ]; do sleep 2; done
ping_up=$(awk '{print int($1)}' /proc/uptime)
until [ "$(curl -s -m 8 -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -H 'X-Requested-With: XMLHttpRequest' -d '{"user":"nobody","password":"x","type":"login"}' http://127.0.0.1:8082/ui/api/v1/ui/auth/login)" = 401 ]; do sleep 2; done
ui_up=$(awk '{print int($1)}' /proc/uptime)
echo "after boot: REST API at $ping_up s, login at $ui_up s of uptime" > /var/log/air-after-boot.log
rm -f /etc/systemd/system/air-after-boot.service
EOF
  sudo chmod 755 /usr/local/sbin/air-after-boot.sh
  sudo tee /etc/systemd/system/air-after-boot.service >/dev/null <<'EOF'
[Unit]
Description=Measures the recovery of JFrog once
After=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/air-after-boot.sh
[Install]
WantedBy=multi-user.target
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable air-after-boot.service 2>/dev/null
  sudo systemctl reboot
fi
