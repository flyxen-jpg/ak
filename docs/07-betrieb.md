# 07 Betriebshandbuch

[Zurück: Bewertung](06-bewertung.md) | [Übersicht](README.md) | [Weiter: Ansible](08-ansible.md)

## Status

```bash
~/ha/status.sh                      # Gesamtstatus aller Komponenten (auf jeder VM des Labors)
watch -n2 -c -t ~/ha/status.sh      # fortlaufend
```

Im Cluster aus dem Ansible-Projekt heißt das Skript `/usr/local/bin/ak-cluster-status` und liegt auf allen Knoten.

| Prüfpunkt | Abfrage | Gesund |
|---|---|---|
| Artifact Keeper bereit für den Load Balancer | `curl http://<knoten>:8080/readyz` | 200 |
| Artifact Keeper im Detail | `curl http://<knoten>:8080/health` | `status: healthy` |
| VIP | `curl -I http://192.168.56.50/readyz` | 200, `X-Served-By` nennt den Knoten mit der VIP |
| HAProxy | `http://<knoten>:8404/` (Statistik) oder `echo 'show servers state' \| sudo socat stdio /var/lib/haproxy/stats` | alle Server `UP`. Im Backend `postgres` steht die Replica absichtlich auf `DOWN`. |
| Patroni | `sudo -u postgres patronictl -c /etc/patroni/patroni.yml list` | ein Leader, die Replica im Zustand `streaming`, Lag 0 |
| etcd | `podman exec etcd etcdctl --endpoints=... endpoint status -w table` | drei Mitglieder, ein Leader |
| Garage | `podman exec garage /garage status` | drei Knoten verbunden |
| OpenSearch | `curl <knoten>:9200/_cluster/health` | `green`, bei einem fehlenden Knoten `yellow` |

## Start und Stopp

Nach einem Neustart starten alle Dienste von selbst. `patroni`, `haproxy` und `keepalived` laufen als systemd-Dienste. Die rootless Container starten im Shell-Labor über `podman-restart.service` mit `loginctl enable-linger rocky`, im Cluster aus Ansible als Quadlet-Units des Dienstkontos `ak` mit Linger.

So wird ein Knoten für eine Wartung geordnet heruntergefahren:

```bash
# 1. aus dem Load Balancing nehmen, auf BEIDEN HAProxy-Knoten
for lb in 192.168.56.11 192.168.56.12; do ssh $lb "echo 'set server ak_api/ak-node1 state drain; set server ak_web/ak-node1 state drain' | sudo socat stdio /var/lib/haproxy/stats"; done
# 2. falls der Knoten Leader ist, geplant umschalten
sudo -u postgres patronictl -c /etc/patroni/patroni.yml switchover --leader ak-node1 --candidate ak-node2 --force
# 3. falls der Knoten die VIP hält, keepalived stoppen, damit die VIP wandert
sudo systemctl stop keepalived
# 4. Knoten herunterfahren
sudo systemctl poweroff
```

Nach dem Wiederanlauf den Server in HAProxy wieder auf `ready` setzen (`set server ak_api/ak-node1 state ready`).

## Update von Artifact Keeper ohne Unterbrechung

Dieses Verfahren wurde getestet.

1. Die neue Version zuerst in Staging testen und die Release Notes auf Schemaänderungen prüfen.
2. Im Shell-Labor `AK_VERSION` in `lab/ha/lab.conf` setzen und `vm/push.ps1` ausführen.
3. Knoten für Knoten vorgehen: Drain, dann `bash ~/ha/60-ak-node.sh <ip> s3`, warten bis `/readyz` 200 liefert, dann wieder `ready`. `vm/failover-test.ps1 -Scenario drain-restart` automatisiert genau das, im Labor ohne einen Fehler.
4. Schemaänderungen führt Artifact Keeper beim Start aus. Für große Migrationen setzt man `SKIP_MIGRATIONS=true` auf allen Knoten und führt die Migration einmal separat aus, siehe `online-migrations.md` im Projekt.

Mit Ansible genügt es, `artifact_keeper_version` und `artifact_keeper_web_version` zu setzen und `playbooks/artifact_keeper.yml` auszuführen. Das Playbook erledigt Drain, Neustart, Warten auf `/readyz` und Freigabe selbst, siehe [08](08-ansible.md).

## Datenbank mit Patroni

| Aufgabe | Befehl |
|---|---|
| Zustand | `patronictl -c /etc/patroni/patroni.yml list` |
| geplanter Wechsel | `patronictl ... switchover --leader <alt> --candidate <neu> --force` |
| Replica neu aufbauen | `patronictl ... reinit ak-pg <mitglied>` |
| Konfiguration ändern | `patronictl ... edit-config`, zum Beispiel für `ttl` oder `synchronous_mode` |
| Wartungsmodus ohne automatischen Failover | `patronictl ... pause` und danach `resume` |

## Backup und Wiederherstellung

Im Labor nicht umgesetzt, hier die Empfehlung:

| Daten | Methode |
|---|---|
| PostgreSQL | pgBackRest oder WAL-G mit Ziel S3 und fortlaufendem WAL-Archiv für Point-in-Time-Recovery |
| Artefakte in S3 | Versionierung oder Replikation des Buckets an einen zweiten Standort. Bei Garage ein zweiter Cluster mit `rclone sync`. |
| OpenSearch | Keine Sicherung nötig. Artifact Keeper baut den Index beim Start vollständig aus der Datenbank neu auf („Full reindex complete“). |
| Konfiguration | Git-Repository mit dem Ansible-Projekt oder `lab/ha/*`, aber ohne Zugangsdaten. Diese gehören in Vault oder einen Passwortmanager. |
| interne Backups von Artifact Keeper | laut Dokumentation über `BACKUP_PATH` und `BACKUP_S3_BUCKET`, nicht getestet |

Eine Probe der Wiederherstellung sollte mindestens alle sechs Monate stattfinden.

## Überwachung

Mindestens diese Punkte gehören in das Monitoring:

* HTTP-Check auf `http://<VIP>/readyz` mit Alarm, wenn länger als 30 Sekunden nicht 200 zurückkommt
* `/health` je Knoten für `database`, `storage` und `opensearch` mit Warnung bei `unhealthy`
* HAProxy: Zustand der Server (`show servers state`) und Anteil der 5xx-Antworten
* Patroni: Rolle, Lag der Replikation und Wechsel der Timeline, denn ein Wechsel bedeutet einen Failover
* etcd: ein Leader vorhanden, drei Mitglieder
* Garage: Zahl der verbundenen Knoten über `garage status`
* OpenSearch: `status` mit Alarm bei `red` und `unassigned_shards`
* Metriken von Artifact Keeper: laut Dokumentation für Prometheus über `METRICS_PORT` (Standard 9091), zum Beispiel `ak_db_pool_connection_failures_total`
* Muster im Log: `Failed to index artifact` zeigt einen veralteten Suchindex an
* Container-Health: `podman ps` muss für `ak-backend` den Zustand `healthy` zeigen

## Fehlersuche

Diese Erfahrungen stammen aus dem Labor.

| Symptom | Ursache | Lösung |
|---|---|---|
| Die VIP ist nur von manchen Clients erreichbar. | IP-Konflikt, im Labor mit dem DHCP-Server von VirtualBox auf `.100` | `arping -D -I <interface> <vip>` und eine freie IP wählen |
| Das Backend startet nach `podman kill` nicht neu. | Podman wertet einen Stopp durch den Administrator als gewollt. | `podman start ak-backend`. Abstürze werden automatisch neu gestartet. |
| Ein Container startet nicht mit `container state improper`. | podman-compose mit `depends_on` auf einen beendeten Init-Container | keine Init-Container in `depends_on`, siehe [02](02-podman-deployment.md) |
| Migration meldet `Migration source URL IP ... is not allowed`. | SSRF-Schutz | `AK_SSRF_ALLOW_PRIVATE_CIDRS=<ip-der-quelle>` |
| Migration meldet `Package type 'gradle' is not supported`. | Gradle lässt sich nicht migrieren. | vorher ein Maven-Repository anlegen |
| Downloads über die REST-API liefern 429. | `RATE_LIMIT_PRESIGN_PER_MIN=30` bei S3 | native Endpunkte nutzen oder das Limit anheben |
| Die Suche findet neue Artefakte nicht. | OpenSearch steht auf RED, weil Replikas fehlen. | `lab/ha/31-opensearch-replicas.sh` ausführen und das Backend neu starten, damit es neu indiziert |
| Alle Clients bekommen kurzzeitig 401. | Ein Failover der Datenbank läuft. | abwarten, höchstens bis zur TTL, und Patroni prüfen |
| Uploads hängen, `/readyz` meldet 200. | Der NFS-Server ist weg (nur in der NFS-Variante). | NFS-Server wiederherstellen, besser S3 statt NFS verwenden |
| Die Patroni-Replica bleibt bei `creating replica` stehen. | `pg_basebackup` wartet auf einen Checkpoint. | abwarten, höchstens bis `checkpoint_timeout` |
| `ssh ... pkill -f <muster>` beendet die eigene Sitzung. | Das Muster steht in der eigenen Kommandozeile. | `pkill -x <name>` oder `pgrep -f '^...'` |
| `ak-backend` startet ohne erkennbaren Grund alle paar Minuten neu. | Der Healthcheck läuft über eine Shell, die das Image nicht hat. | `HealthCmd` in der Exec-Form als JSON-Liste angeben, siehe [08](08-ansible.md) |
| Das Backend startet nicht mit `must decode to exactly 32 bytes`. | falsches Format von `AK_WEBHOOK_SECRET_KEY` oder einem der anderen Schlüssel | `openssl rand -base64 32` |

## Härtung vor dem Produktivbetrieb

* TLS am Frontend von HAProxy, Umleitung von HTTP auf HTTPS und `AK_EXTERNAL_URL=https://...`
* TLS oder mTLS für etcd, die RPC- und S3-Verbindungen von Garage sowie das Security-Plugin von OpenSearch aktivieren
* Zugangsdaten aus Vault oder Dateien statt aus `.env` laden. Artifact Keeper unterstützt dafür Varianten mit `*_FILE`, siehe `file-based-secrets.md` im Projekt.
* `ENVIRONMENT=production` und `CORS_ORIGINS` auf die echte Domain setzen, das Admin-Passwort wechseln und lokale Admin-Konten auf ein Minimum beschränken
* In der Firewall die Clusterports nur im Clusternetz öffnen (im Shell-Labor die Zone `lab`, im Cluster aus Ansible `ak-cluster`) und VRRP nur zwischen den Knoten mit Load Balancer zulassen
