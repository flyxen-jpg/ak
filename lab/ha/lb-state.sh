#!/usr/bin/env bash
# Zeigt Betriebs- und Admin-Zustand der AK-Server in HAProxy (srv_op_state 2=UP, srv_admin_state 0=ready, 8=drain, 1/4=maint)
for b in ak_api ak_web; do
  echo "show servers state $b" | sudo socat stdio /var/lib/haproxy/stats | awk -v b=$b 'NR>2 && NF {print "  " b "/" $4 "  op_state=" $6 "  admin_state=" $7 "  weight=" $8}'
done
