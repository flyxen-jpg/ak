#---------------------------------------------------------------------
# HAProxy auf ak-node1/ak-node2 (identisch). Der aktive Knoten haelt die VIP (keepalived).
#   :80    Artifact Keeper (API/Formate -> Backends :8080, UI -> Web :3000)
#   :5000  PostgreSQL -> nur der aktuelle Patroni-Primary (Health: Patroni-REST /primary)
#   :3910  Garage-S3 (alle 3 Knoten)
#   :9201  OpenSearch (alle 3 Knoten)
#   :8404  Statistikseite
#---------------------------------------------------------------------
global
    log /dev/log local0
    maxconn 4000
    user haproxy
    group haproxy
    daemon
    stats socket /var/lib/haproxy/stats mode 660 level admin

defaults
    log global
    option dontlognull
    retries 2
    option redispatch
    timeout connect 5s
    timeout client 15m
    timeout server 15m
    timeout http-request 30s
    timeout check 3s

listen stats
    bind *:8404
    mode http
    stats enable
    stats uri /
    stats refresh 5s
    stats show-node

#--------------------------- Artifact Keeper --------------------------
frontend ak
    bind *:80
    mode http
    option httplog
    option forwardfor
    http-request set-header X-Forwarded-Proto http
    # Diagnose: welcher HAProxy (= VIP-Halter) und welches Backend hat geantwortet
    http-response set-header X-Served-By %[hostname]
    http-response set-header X-AK-Backend %s
    # gleiche Aufteilung wie der offizielle Caddyfile: Backend-Pfade vs. Web-UI
    acl is_backend path_beg /api/ /v2 /health /healthz /livez /readyz /ready /metrics /swagger-ui
    acl is_backend path_beg /general/ /maven/ /npm/ /pypi/ /nuget/ /cargo/ /gems/ /go/ /helm/
    acl is_backend path_beg /debian/ /rpm/ /alpine/ /pacman/ /composer/ /conan/ /conda/ /t/ /swift/
    acl is_backend path_beg /terraform/ /cocoapods/ /hex/ /pub/ /lfs/ /ivy/ /chef/ /puppet/ /ansible/
    acl is_backend path_beg /cran/ /bazel/ /huggingface/ /jetbrains/ /vscode/ /proto/ /incus/ /lxc/ /ext/
    use_backend ak_api if is_backend
    default_backend ak_web

backend ak_api
    mode http
    balance roundrobin
    option httpchk GET /readyz
    http-check expect status 200
    default-server inter 2s fall 2 rise 2 slowstart 10s
    server ak-node1 @IP_NODE1@:8080 check
    server ak-node2 @IP_NODE2@:8080 check

backend ak_web
    mode http
    balance roundrobin
    option httpchk GET /
    http-check expect status 200-399
    default-server inter 3s fall 2 rise 2
    server ak-node1 @IP_NODE1@:3000 check
    server ak-node2 @IP_NODE2@:3000 check

#--------------------------- PostgreSQL (Patroni) --------------------
listen postgres
    bind *:5000
    mode tcp
    option httpchk OPTIONS /primary
    http-check expect status 200
    default-server inter 2s fall 2 rise 2 on-marked-down shutdown-sessions
    server ak-node1 @IP_NODE1@:5432 maxconn 150 check port 8008
    server ak-node2 @IP_NODE2@:5432 maxconn 150 check port 8008

#--------------------------- Garage S3 -------------------------------
listen s3
    bind *:3910
    mode http
    balance leastconn
    option httpchk GET /health
    http-check expect status 200
    default-server inter 3s fall 2 rise 2
    server rocky10  @IP_INFRA@:3900 check port 3903
    server ak-node1 @IP_NODE1@:3900 check port 3903
    server ak-node2 @IP_NODE2@:3900 check port 3903

#--------------------------- OpenSearch ------------------------------
listen opensearch
    bind *:9201
    mode http
    balance roundrobin
    option httpchk GET /_cluster/health
    http-check expect status 200
    default-server inter 3s fall 2 rise 2
    server rocky10  @IP_INFRA@:9200 check
    server ak-node1 @IP_NODE1@:9200 check
    server ak-node2 @IP_NODE2@:9200 check
