# 05 Testprotokoll Hochverfügbarkeit und Failover

[Zurück: Hochverfügbarkeit](04-hochverfuegbarkeit.md) | [Übersicht](README.md) | [Weiter: Bewertung](06-bewertung.md)

Getestet am 3. und 4. November 2026 auf einem Cluster aus zwei Knoten mit Artifact Keeper und einem Quorum Knoten (siehe [04](04-hochverfuegbarkeit.md)), Artifact Keeper 1.11.11, Speicher S3 mit Garage.

## Messmethode

* Ein externer Client (`vm/probe.ps1` auf dem Windows Host) sendet etwa alle 0,25 Sekunden einen Download über die VIP an den nativen Endpunkt `/general/generic-files/...` mit 3 Sekunden Timeout sowie einen Upload über die REST API mit 5 Sekunden Timeout. Protokolliert werden HTTP Code, Latenz, der Knoten mit der VIP (`X-Served-By`) und das bedienende Backend (`X-AK-Backend`).
* Ein interner Client (`lab/ha/probe-vip.sh` auf ak-node1) fragt alle 0,2 Sekunden `GET /readyz` über die VIP ab. Damit lassen sich Effekte des Host Only Adapters von VirtualBox unter Windows abgrenzen.
* Jedes Szenario (`vm/failover-test.ps1`) beginnt mit 15 Sekunden Normalbetrieb, dann folgt die Aktion und anschließend eine Beobachtung von 30 bis 120 Sekunden. `vm/failover-all.ps1` führt alle Szenarien samt Wiederherstellung aus. Die Rohdaten liegen unter `lab/results/`.

## Übersicht

| Nr. | Szenario | Lesen: Fehler, längste Lücke | Schreiben: Fehler, längste Lücke | Selbstheilung |
|---|---|---|---|---|
| 1 | Rolling Restart ohne Drain | 2 von 681, unter 0,2 s | nicht gemessen | ja |
| 2 | Rolling Restart mit Drain in HAProxy | 0, 0 s | 0, 0 s | ja |
| 3 | Absturz eines Backend Prozesses (`kill -9`) | 0, 0 s | 1, 0,7 s (laufender Upload) | ja, Podman startet neu |
| 4 | Geplanter Wechsel der Datenbank (`patronictl switchover`) | 2, 5,2 s | 1, 4,3 s | ja |
| 5 | Absturz des Primary (PostgreSQL und Patroni mit `kill -9`) | 87, 29,7 s | 87, 29,7 s | ja, die Replica übernimmt nach Ablauf der TTL |
| 6 | Ausfall eines Garage Knotens | 0, 0 s | 0, 0 s | ja |
| 7 | Knoten hart aus (hält VIP und Primary) | 98, 36,2 s | 97, 35,5 s | ja, VIP und Datenbank wechseln |
| 8 | Der ausgefallene Knoten kommt zurück | 0, 0 s | 0, 0 s | ja, Rückkehr als Replica, die VIP bleibt dank `nopreempt` |
| 9 | Quorum Knoten hart aus (etcd, Garage und OpenSearch von drei auf zwei) | intern 0 Fehler bei 348 Anfragen | nicht gemessen | ja |
| 10 | NFS statt S3, der NFS Server fällt aus | Downloads hängen bis zur Rückkehr | nicht gemessen | erst nach Rückkehr des NFS Servers |

## Einzelheiten

### Szenario 1 und 2: Rolling Restart

Ohne Drain trafen 2 von 681 Anfragen (0,3 Prozent) einen Container genau im Moment des Stopps und bekamen HTTP 502. Wird der Knoten vorher über den Admin Socket von HAProxy mit `set server ak_api/<knoten> state drain` aus dem Verkehr genommen, gibt es keinen einzigen Fehler. Der Drain gehört deshalb fest in jedes Update, siehe [07](07-betrieb.md).

### Szenario 3: Absturz des Backends

Ein laufender Upload schlug mit 502 fehl. Uploads sind nicht idempotent, HAProxy wiederholt sie zu Recht nicht. Build Werkzeuge wie Maven, Gradle oder npm wiederholen selbst. Podman startete den Container dank `restart: always` automatisch neu.

Wichtig bei Podman: `podman kill` oder `podman stop` durch einen Administrator gilt als gewollt, der Container wird dann nicht neu gestartet. Nur ein echter Absturz löst die Restart Policy aus.

### Szenario 4 und 5: Datenbank

Der geplante Wechsel dauerte etwa 4 Sekunden, die Clients waren rund 5 Sekunden eingeschränkt. Beim unkontrollierten Absturz stürzt Patroni mit ab und kann die Leader Sperre in etcd nicht freigeben. Die Replica übernimmt daher erst nach Ablauf der TTL von 30 Sekunden. In dieser Zeit liefert HAProxy sauber 503, weil kein Backend auf `/readyz` bereit meldet. Der alte Primary kehrte per `pg_rewind` automatisch als Replica zurück. Über alle Tests stieg die Timeline von 2 über 3 auf 4.

Auffällig ist, dass Artifact Keeper in der kurzen Zeit ohne Datenbank teilweise mit 401 statt 503 antwortet. Die Passwortprüfung schlägt fehl und wird als fehlgeschlagener Login gemeldet. Clients sehen dann scheinbar falsche Zugangsdaten, im ungünstigen Fall zählen solche Versuche sogar zur Kontosperre.

Mit `ttl: 20`, `loop_wait: 5` und `retry_timeout: 5` sinkt die Failover Zeit auf etwa 15 bis 20 Sekunden, das System reagiert dann aber empfindlicher auf kurze Netzstörungen. Für Betrieb ohne jeden Datenverlust kommt `synchronous_mode: true` hinzu.

### Szenario 7: Knoten hart aus

| Zeit | Ereignis |
|---|---|
| T | ak-node1 wird hart ausgeschaltet. Er hält VIP und Primary und ist Mitglied von etcd, Garage und OpenSearch. |
| T plus 8 s | Die VIP antwortet von ak-node2. Darin enthalten sind 3 Sekunden Timeout der hängenden Anfrage. |
| T plus 9 bis 35 s | 503, der Failover der Datenbank läuft (Patroni TTL). |
| T plus 36 s | ak-node2 bedient wieder vollständig. |

Den Ausschlag gibt die Failover Zeit der Datenbank, nicht keepalived und nicht Artifact Keeper.

### Szenario 9: Quorum Knoten aus

* Intern gab es keinen Fehler bei 348 Anfragen. etcd, Garage und OpenSearch arbeiten mit zwei von drei Mitgliedern weiter.
* Der externe Client unter Windows sah dabei bis zu etwa 50 Sekunden lang Timeouts. Laut den Logs von HAProxy kamen in dieser Zeit keine Anfragen vom Windows Host an. Das ist ein Effekt des Labors: Der Host Only Adapter von VirtualBox stockt unter Windows, wenn eine VM hart ausgeschaltet wird. Gegen den Cluster spricht das nicht.
* Im ersten Durchlauf ging OpenSearch auf RED. Artifact Keeper legt die Indizes `artifacts` und `repositories` mit 0 Replikas an. Neue Artefakte wurden daraufhin nicht mehr indiziert (`Failed to index artifact ... HTTP 503`), die Suche war unvollständig. Up- und Downloads liefen weiter, weil die Suche für `/readyz` optional ist. Abhilfe schafft ein Index Template mit `number_of_replicas: 1` (`lab/ha/31-opensearch-replicas.sh`). In der Wiederholung blieb der Cluster gelb und die Indizierung lief ohne Fehler weiter.
* Der Speichertest in `/health` meldete mit zwei von drei Garage Knoten zeitweise `Storage probe timed out (2s)`, ohne Folgen für Up- und Downloads.

### Szenario 10: NFS statt S3

| Prüfung | Ergebnis |
|---|---|
| Upload über node1, Download über node2 | identische Prüfsumme |
| UID Zuordnung bei rootless Podman | funktioniert mit `all_squash,anonuid=<subuid+1000>`, beide Knoten haben denselben subuid Bereich |
| NFS Server fällt aus | Downloads hängen bis zum Timeout, `/readyz` meldet aber weiter 200. HAProxy kann daher nicht umleiten. |
| NFS Server kommt zurück | Dank `hard`-Mount läuft die Ein- und Ausgabe automatisch weiter. |

Mit NFS ist der NFS Server ein Single Point of Failure für den ganzen Cluster. Sinnvoll ist das nur mit einem hochverfügbaren NAS.

## Weitere Beobachtungen

* Die REST API für Downloads ist bei S3 auf 30 Anfragen pro Minute und IP begrenzt (`RATE_LIMIT_PRESIGN_PER_MIN`). Die nativen Endpunkte haben dieses Limit nicht (200 von 200 erfolgreich).
* Der Migrationsjob läuft auf dem Knoten, der die Startanfrage erhält. Ein Knotenausfall während einer Migration wurde nicht getestet. Laut Code setzt ein erneuter Start die Arbeit fort, Duplikate werden per SHA-256 übersprungen.
* Nachdem der Quorum Knoten wieder lief, war node1 kurz nicht im Pool von HAProxy, nur node2 bediente. Fehler für Clients gab es nicht, die Ursache blieb ungeklärt. Die Zustände der Server in HAProxy sollten deshalb überwacht werden.
* Ressourcenbedarf: Backend etwa 40 MB RAM, Web 110 bis 230 MB, OpenSearch etwa 630 MB bei 256 MB Heap, Garage etwa 45 MB, etcd etwa 50 MB.

## Ergänzende Tests am Cluster aus Ansible

Am Cluster, den das Ansible Projekt offline aufgebaut hat (siehe [09](09-offline.md)), wurden zwei Szenarien wiederholt. Gemessen wurde von innen mit `lab/ha/probe-vip-ansible.sh` alle 0,5 Sekunden.

| Szenario | Ergebnis |
|---|---|
| Rolling Update per Playbook `artifact_keeper.yml` | 0 Fehler bei 106 Anfragen |
| Knoten hart aus, hält VIP und Primary | etwa 44 Sekunden Unterbrechung, nach dem Booten automatische Rückkehr als Replica |

Im ersten Durchgang dauerte die Unterbrechung 79 Sekunden. Die Ursache war ein fehlerhafter Healthcheck, der das Backend auf dem verbliebenen Knoten mitten im Failover neu startete. Die Erklärung steht in [08](08-ansible.md).
