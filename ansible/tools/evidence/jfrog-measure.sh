#!/bin/bash
# Measures one JFrog configuration on the VM that runs the role artifactory_oss.
#   RT_PASSWORD=... jfrog-measure.sh <label> [fresh|restart] [extra env file]
# fresh    removes containers and data, as on a first installation
# restart  keeps the data
# The extra env file holds lines that are added to artifactory.env for this measurement. The
# role's own file is restored afterwards. Output: one result block and one CSV line in
# ~/jfrog-measure.csv. Every timing is counted from the moment the unit is started.
set -uo pipefail
# The service account cannot enter the home directory of the caller.
cd /
label=${1:?label}
mode=${2:-restart}
extra=${3:-}
password=${RT_PASSWORD:?RT_PASSWORD}
url=http://127.0.0.1:8082
env_file=/etc/artifactory/artifactory.env
ak_uid=$(id -u ak)
as_ak() { sudo -u ak XDG_RUNTIME_DIR="/run/user/$ak_uid" "$@"; }
now() { date +%s.%N; }
since() { python3 -c "print(round($(now)-$1,1))"; }

as_ak systemctl --user stop artifactory.service
if [ "$mode" = fresh ]; then
  as_ak systemctl --user stop artifactory-postgres.service
  as_ak podman volume rm -f artifactory-data artifactory-postgres-data >/dev/null
  as_ak systemctl --user start artifactory-postgres.service
  until as_ak podman exec artifactory-postgres pg_isready -q -U artifactory -d artifactory 2>/dev/null; do sleep 1; done
fi

sudo cp -p "$env_file" "$env_file.measure-orig"
trap 'sudo mv -f "$env_file.measure-orig" "$env_file"' EXIT
if [ -n "$extra" ]; then
  # Later lines of an env file win, so a profile can replace a value of the role.
  sudo sh -c "cat '$extra' >> '$env_file'"
fi

t0=$(now)
as_ak systemctl --user start --no-block artifactory.service
t_router='' t_all='' t_ping='' t_login='' services='' codes=''
limit=${MEASURE_TIMEOUT:-420}
while :; do
  elapsed=$(since "$t0")
  [ "${elapsed%.*}" -ge "$limit" ] && break
  health=$(curl -s -m 3 "$url/router/api/v1/system/health" || true)
  if [ -n "$health" ]; then
    read -r router_state all_state services < <(python3 -c '
import json,sys
try:
    d=json.loads(sys.argv[1])
    s=d.get("services",[])
    bad=[x["service_id"].split("@")[0] for x in s if x.get("state")!="HEALTHY"]
    print(d.get("router",{}).get("state","?"), "yes" if s and not bad else "no", ",".join(bad) or "-")
except Exception:
    print("? no ?")' "$health")
    [ -z "$t_router" ] && [ "$router_state" = HEALTHY ] && t_router=$(since "$t0")
    [ -z "$t_all" ] && [ "$all_state" = yes ] && t_all=$(since "$t0")
  fi
  if [ -z "$t_ping" ] && [ "$(curl -s -m 3 "$url/artifactory/api/system/ping")" = OK ]; then
    t_ping=$(since "$t0")
  fi
  if [ -n "$t_ping" ] && [ -z "$t_login" ]; then
    code=$(curl -s -m 30 -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -H 'X-Requested-With: XMLHttpRequest' \
      -d "$(python3 -c 'import json,os;print(json.dumps({"user":"admin","password":os.environ["RT_PASSWORD"],"type":"login"}))')" \
      "$url/ui/api/v1/ui/auth/login")
    # On a fresh installation the password is still the default one, so 401 also proves the UI answers.
    [ "${codes##* }" = "$code" ] || codes="$codes $(since "$t0"):$code"
    case "$code" in 200|401) t_login=$(since "$t0") ;; esac
  fi
  [ -n "$t_all" ] && [ -n "$t_ping" ] && [ -n "$t_login" ] && break
  sleep 1
done

pid=$(as_ak podman inspect -f '{{.State.Pid}}' artifactory 2>/dev/null)
cgroup=/sys/fs/cgroup$(sed -n 's/^0:://p' "/proc/$pid/cgroup" 2>/dev/null)
sleep "${MEASURE_SETTLE:-60}"
mem_current=$(($(sudo cat "$cgroup/memory.current" 2>/dev/null || echo 0)/1048576))
mem_peak=$(($(sudo cat "$cgroup/memory.peak" 2>/dev/null || echo 0)/1048576))
swap=$(($(sudo cat "$cgroup/memory.swap.current" 2>/dev/null || echo 0)/1048576))
available=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)

echo "=== $label ($mode)"
echo "router healthy ${t_router:-timeout} s, all services ${t_all:-timeout} s, ping ${t_ping:-timeout} s, UI answers ${t_login:-timeout} s"
[ -z "$t_all" ] && echo "not healthy: $services"
echo "login answers (time:code):$codes"
echo "--- heap settings"
for j in $(pgrep -x java); do tr '\0' ' ' < /proc/$j/cmdline | grep -oE '(-Xmx[^ ]+|-XX:MaxRAMPercentage=[0-9]+|-XX:\+Use[A-Za-z0-9]+GC|-Dcatalina.base=[^ ]+|jfbus|topology|jfconfig)' | sort -u | tr '\n' ' ' | cut -c1-170; echo; done
echo "memory $mem_current MB, peak $mem_peak MB, swap $swap MB, host available $available MB"
echo "--- processes by memory (resident plus swapped)"
sudo sh -c "for p in \$(cat '$cgroup/cgroup.procs' 2>/dev/null; find '$cgroup' -name cgroup.procs -exec cat {} + 2>/dev/null); do
  [ -r /proc/\$p/status ] || continue
  rss=\$(awk '/VmRSS|VmSwap/{s+=\$2}END{print int(s/1024)}' /proc/\$p/status)
  [ -n \"\$rss\" ] || continue
  cmd=\$(tr '\0' ' ' < /proc/\$p/cmdline | sed -E 's/.*(jf-[a-z-]+|-Djf\.product\.home[^ ]*|artifactory[a-z.-]*|access|router|metadata|event|frontend|observability|jfconnect|topology|onemodel|evidence|jfconfig|node|traefik).*/\1/' | cut -c1-30)
  echo \"\$rss \$(cat /proc/\$p/comm) \$cmd\"
done" | sort -u | sort -rn | tee /var/tmp/measure-procs.$$ | head -"${MEASURE_TOP:-16}"
sum=$(awk '{s+=$1}END{print s}' /var/tmp/measure-procs.$$); rm -f /var/tmp/measure-procs.$$
echo "sum of processes $sum MB"
pg_conn=$(as_ak podman exec artifactory-postgres psql -U artifactory -d artifactory -Atc "select count(*) from pg_stat_activity" 2>/dev/null)
pg_pid=$(as_ak podman inspect -f '{{.State.Pid}}' artifactory-postgres 2>/dev/null)
pg_cg=/sys/fs/cgroup$(sed -n 's/^0:://p' "/proc/$pg_pid/cgroup" 2>/dev/null)
echo "postgres: $pg_conn connections, memory $(($(sudo cat "$pg_cg/memory.current" 2>/dev/null || echo 0)/1048576)) MB"

# Functional test: repository listing, generic upload, parallel download and registry access.
auth="admin:$password"
result_list=$(curl -s -m 30 -o /dev/null -w '%{http_code} %{time_total}' -u "$auth" "$url/artifactory/api/repositories")
echo "repository list: $result_list"
if [ "${MEASURE_LOAD:-yes}" = yes ]; then
  repo=${MEASURE_REPO:-generic-tools}
  file=/var/tmp/measure-$$.bin
  head -c 20971520 /dev/urandom > "$file"
  put=$(curl -s -m 120 -o /dev/null -w '%{http_code} %{time_total}' -u "$auth" -T "$file" "$url/artifactory/$repo/measure/$label.bin")
  echo "upload 20 MB: $put"
  start=$(now)
  seq 1 40 | xargs -P 8 -I{} curl -s -m 120 -o /dev/null -u "$auth" "$url/artifactory/$repo/measure/$label.bin"
  echo "download 40 x 20 MB with 8 clients: $(since "$start") s"
  start=$(now)
  seq 1 200 | xargs -P 16 -I{} curl -s -m 60 -o /dev/null -u "$auth" "$url/artifactory/api/storage/$repo/measure/$label.bin"
  echo "200 metadata requests with 16 clients: $(since "$start") s"
  curl -s -m 30 -o /dev/null -u "$auth" -X DELETE "$url/artifactory/$repo/measure/$label.bin"
  rm -f "$file"
fi
mem_after=$(($(sudo cat "$cgroup/memory.current" 2>/dev/null || echo 0)/1048576))
mem_peak_after=$(($(sudo cat "$cgroup/memory.peak" 2>/dev/null || echo 0)/1048576))
echo "after load: memory $mem_after MB, peak $mem_peak_after MB"
echo "$label,$mode,${t_router:-},${t_all:-},${t_ping:-},${t_login:-},$sum,$mem_current,$mem_peak,$swap,$mem_after,$mem_peak_after" >> ~/jfrog-measure.csv
