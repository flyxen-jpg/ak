# 08 Automatisierte Installation mit Ansible

[Zurück: Betriebshandbuch](07-betrieb.md) | [Übersicht](README.md) | [Weiter: Offline Installation](09-offline.md)

Der HA Aufbau aus [04](04-hochverfuegbarkeit.md) ist als Ansible Projekt unter [`ansible/`](../ansible/) umgesetzt. Es installiert den kompletten Cluster auf frisch installierte VMs mit Rocky Linux 10 Minimal. Auf dem Steuerknoten muss nur `ansible-core` installiert sein, auf den Zielknoten nichts außer dem Minimalsystem. Dasselbe Projekt deckt drei Szenarien ab.

| Szenario | Inventory | Quelle für Pakete und Images | Stand |
|---|---|---|---|
| VirtualBox mit Internet | `inventories/virtualbox-online` | Spiegelserver von Rocky, EPEL und PGDG sowie die öffentlichen Registries | auf frischen VMs getestet, ein zweiter Lauf ändert nichts |
| VirtualBox ohne Internet | `inventories/virtualbox-offline` | Offline Bundle | auf frischen VMs ohne NAT getestet, siehe [09](09-offline.md) |
| Zwei VMs ohne Internet, gehärtet | `inventories/airgap-jfrog`, `inventories/airgap-external` | Offline Bundle, Profil `two_vm` | auf frischen VMs getestet, siehe [13](13-airgap-zwei-vms.md) |
| ohne VirtualBox und ohne Internet, etwa VMware, KVM oder Bare Metal | `inventories/airgapped` als Vorlage | Offline Bundle | nicht getestet. Die Rollen sind dieselben wie oben, nur das Inventory unterscheidet sich, siehe Abschnitt „Ohne VirtualBox“. |

Code und Kommentare sind auf Englisch gehalten und erklären jeweils knapp, was eine Aufgabe tut, warum und wie. Eine Kurzreferenz für Entwickler steht in [`ansible/README.md`](../ansible/README.md).

## Aufbau

```text
ansible/
├── ansible.cfg              kein Standard-Inventory, become nur je Task, Pipelining, Fact-Cache
├── requirements.yml         ansible.posix 2.2.2, fest eingetragen
├── inventories/
│   ├── virtualbox-online/   hosts.yml und group_vars/all/ mit main.yml, secrets.yml, vault.yml
│   ├── virtualbox-offline/
│   └── airgapped/           Vorlage für beliebige Plattformen ohne Internet
├── playbooks/
│   ├── site.yml             ruft nacheinander prepare, infrastructure, database, loadbalancer, artifact_keeper und verify auf
│   ├── prepare.yml          offline_repo (nur offline) und base
│   ├── infrastructure.yml   etcd, garage, opensearch auf allen drei Knoten
│   ├── database.yml         patroni auf ak_app
│   ├── loadbalancer.yml     haproxy und keepalived auf ak_app
│   ├── artifact_keeper.yml  Images parallel laden, danach Rollout mit serial: 1
│   ├── verify.yml           Test über die VIP von Anfang bis Ende
│   └── bundle.yml           baut das Offline-Bundle
├── roles/                   offline_repo, base, podman, etcd, garage, opensearch,
│                            patroni, haproxy, keepalived, artifact_keeper
└── tools/                   generate-vault.py, install-control-node.sh
```

### Gruppen

| Gruppe | Hosts im Labor | Dienste |
|---|---|---|
| `ak_cluster` | alle | etcd, Garage und OpenSearch mit je drei Mitgliedern, ein Ausfall wird verkraftet |
| `ak_app` | ans-node1, ans-node2 | Artifact Keeper, PostgreSQL mit Patroni, HAProxy, keepalived |
| `ak_quorum` | ans-node3 | nur die dritte Stimme für etcd, Garage und OpenSearch |

### Rollen

| Rolle | Aufgabe | Begründung |
|---|---|---|
| `offline_repo` | entpackt das RPM Repository aus dem Bundle nach `/opt/ak-offline/<BUNDLE_ID>`, legt `ak-offline.repo` an und schaltet alle anderen Repositories ab | Ein Repository über `file://` braucht keinen Webserver. dnf löst trotzdem die Abhängigkeiten auf und prüft die Signaturen von Rocky, EPEL und PGDG. |
| `base` | Basispakete, sysctl, chrony, `/etc/hosts`, Firewall Zone `ak-cluster`, Statusskript `ak-cluster-status` | Die Clusterports sind nur im Clusternetz offen. Die Netzwerkkarte wird aus der IP erkannt, egal ob sie enp0s8, ens192 oder bond0 heißt. |
| `podman` | Podman, Dienstkonto `ak` ohne Login, Linger, Verzeichnis für Quadlet. `tasks/image.yml` stellt Images bereit, online per `pull`, offline per `load`. | Rootless bedeutet, dass ein Ausbruch aus dem Container nur ein Konto ohne sudo erreicht. Quadlet statt podman compose ergibt echte systemd Units und kommt ohne EPEL aus. |
| `etcd` | drei Mitglieder als Quadlet | DCS für Patroni |
| `garage` | S3 Knoten, Layout, Bucket und Import des Schlüssels | Schlüssel ID und Secret kommen aus dem Vault. So kennen alle Knoten sie, ohne dass erzeugte Werte zwischen ihnen ausgetauscht werden müssen. |
| `opensearch` | drei Knoten, Index Template mit einer Replika | Artifact Keeper legt seine Indizes sonst ohne Replika an, siehe [05](05-testprotokoll.md). |
| `patroni` | PostgreSQL 18 von PGDG mit Patroni und TLS. Ein Skript nach dem Bootstrap legt die Datenbank für Artifact Keeper an. | Die Datenbank läuft als systemd Dienst unabhängig von der Container Laufzeit. Der erste Knoten initialisiert, der zweite klont. |
| `haproxy` | gleiche Konfiguration auf beiden App Knoten, vor dem Schreiben geprüft | einziger Zugang für Clients und lokale Endpunkte für Datenbank (nur Primary), S3 und Suche |
| `keepalived` | VRRP per Unicast, `nopreempt`, `track_process haproxy`, Prüfung auf eine bereits belegte VIP per `arping` | Im ersten Labor kollidierte die VIP mit dem DHCP Server von VirtualBox, siehe [01](01-laborumgebung.md). |
| `artifact_keeper` | Backend und Web als Quadlet, Umgebungsdatei, Warten auf Bereitschaft | Die Handler arbeiten nacheinander Drain, Neustart, Warten auf `/readyz` und Freigabe ab. Konfigurationsänderungen laufen so ohne Unterbrechung. |

## Umsetzung der Best Practices von ATIX

| Empfehlung | Umsetzung im Projekt |
|---|---|
| `true` und `false`, zwei Leerzeichen Einrückung, keine Listen in einer Zeile | durchgängig, `yamllint` mit `truthy: [true, false]` prüft das |
| jede Task mit einem aussagekräftigen Namen, der groß beginnt | durchgängig, `ansible-lint` prüft das mit den Regeln `name[*]` |
| Modulparameter als Dictionary statt `key=value` | durchgängig |
| vollständige Modulnamen, also `ansible.builtin.copy` statt `copy` | durchgängig, geprüft mit der Regel `fqcn` |
| `become` je Task statt im Play | `become = false` in der `ansible.cfg`, jede privilegierte Task setzt `become: true` |
| `command` und `shell` vermeiden, sonst idempotent machen | nur wo es kein Modul gibt (Garage CLI, `loginctl`, `podman`, `openssl`), immer mit `creates`, `changed_when` oder vorheriger Prüfung |
| alle Geheimnisse mit ansible vault verschlüsseln | `vault.yml` ist verschlüsselt, die Passwortdatei liegt außerhalb des Repositorys |
| Zwischenschicht für lesbare Variablennamen | `secrets.yml`, zum Beispiel `patroni_app_password: "{{ vault_patroni_app_password }}"` |
| `import_*` vor `include_*` | `import_tasks` und `import_playbook`. `include_role` nur für die Schleife über die Images, weil sie dynamisch sein muss. |
| Rollen zur Wiederverwendung, Unterscheidung von `defaults` und `vars` | jede Komponente eine Rolle, alles Einstellbare in `defaults/` |
| Rollenvariablen mit dem Rollennamen als Präfix | `etcd_*`, `garage_*` und so weiter. Werte für die ganze Umgebung heißen `ak_*` und stehen im Inventory. `ansible-lint` prüft das mit `var-naming[no-role-prefix]`. |
| ungenutzte Verzeichnisse einer Rolle löschen | nur Verzeichnisse, die auch genutzt werden (`defaults`, `tasks`, `handlers`, `templates`, `meta`) |
| Templates mit `ansible_managed` und der erzeugenden Rolle kennzeichnen | Jedes Template beginnt mit `# {{ ansible_managed }}` und `# This file was created from the role: {{ ansible_role_name }}`. |

Eine Abweichung ist bewusst gewählt. ATIX empfiehlt, `ansible_managed` in der `ansible.cfg` anzupassen. Diese Option ist in aktuellen Versionen von ansible core abgekündigt, sie fällt mit 2.23 weg, und ansible lint warnt davor. Das Projekt nutzt deshalb den Standardtext. Datum oder Benutzer im Kopf der Dateien würden außerdem bei jedem Lauf eine Änderung erzeugen.

`ansible-lint` im strengsten Profil `production` und `yamllint` melden für alle 139 Dateien weder Fehler noch Warnungen, einschließlich der Rollen für Einzelknoten, Bootstrap und Migration aus [10](10-einzelknoten.md) und [11](11-nat-netzwerk.md).

## Voraussetzungen

| | Steuerknoten | Zielknoten |
|---|---|---|
| Betriebssystem | Rocky Linux oder RHEL 10 | Rocky Linux oder RHEL 10 Minimal |
| Software | `ansible-core` ab 2.16, AppStream liefert 2.16.16 | nichts weiter. Python 3, `tar` und die Python Bindings für SELinux gehören zur Minimalinstallation. |
| Zugang | SSH Schlüssel | Benutzer mit sudo ohne Passwort, statische IP im Clusternetz |
| Netz | erreicht alle Knoten per SSH | gemeinsames Layer 2 Netz für die VIP (VRRP) |

## Ablauf mit Internet

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml -p collections
tools/generate-vault.py inventories/virtualbox-online/group_vars/all/vault.yml
export ANSIBLE_VAULT_PASSWORD_FILE=~/.ansible/ak-vault-pass
ansible-playbook -i inventories/virtualbox-online/hosts.yml playbooks/site.yml
```

`generate-vault.py` erzeugt alle Geheimnisse im jeweils verlangten Format und verschlüsselt sie sofort. Garage bekommt Hexwerte und eine Schlüssel ID mit `GK`, keepalived ein Passwort mit acht Zeichen, Artifact Keeper Base64 von genau 32 Byte. Einen vorhandenen Vault überschreibt das Skript nie, weil die Werte dann bereits im Cluster stecken.

Einzelne Teile lassen sich getrennt ausführen:

```bash
ansible-playbook -i inventories/<env>/hosts.yml playbooks/site.yml --tags haproxy     # nur HAProxy
ansible-playbook -i inventories/<env>/hosts.yml playbooks/artifact_keeper.yml         # Update von Artifact Keeper, Knoten für Knoten
ansible-playbook -i inventories/<env>/hosts.yml playbooks/infrastructure.yml -e infrastructure_serial=1
ansible-playbook -i inventories/<env>/hosts.yml playbooks/verify.yml                   # Funktionstest
```

### Update von Artifact Keeper

`artifact_keeper_version` und `artifact_keeper_web_version` in `group_vars` setzen und `playbooks/artifact_keeper.yml` ausführen. Das Playbook lädt die Images zuerst parallel auf alle Knoten. Danach nimmt es Knoten für Knoten aus HAProxy, startet ihn neu, wartet auf `/readyz` und gibt ihn wieder frei. Mit diesem Verfahren traten im Test keine Fehler auf, siehe [05](05-testprotokoll.md). Ohne Internet muss vorher ein neues Bundle gebaut werden.

### Änderungen an etcd, Garage und OpenSearch im laufenden Betrieb

Die Erstinstallation läuft auf allen Knoten gleichzeitig, denn ein neuer etcd Cluster wird nur gesund, wenn seine Mitglieder gemeinsam starten. Für spätere Änderungen gibt es `-e infrastructure_serial=1`. Dann wird ein Knoten nach dem anderen bearbeitet, und die Health Checks jeder Rolle warten, bis der Knoten wieder im Cluster ist. Zusätzlich starten die Handler höchstens einen Knoten gleichzeitig neu (`throttle: 1`).

## Testergebnisse

Getestet wurde mit VirtualBox 7.2 auf vier frischen VMs aus dem Kickstart dieses Repositorys: `ans-ctl` mit 1,25 GB und nur `ansible-core`, `ans-node1` und `ans-node2` mit je 3 GB sowie `ans-node3` mit 2 GB. Die VIP lag auf 192.168.56.60.

| Test | Ergebnis |
|---|---|
| Erstinstallation mit Internet (`site.yml`) | erfolgreich, alle Komponenten gesund, Upload und Download über die VIP |
| zweiter Lauf zur Prüfung der Idempotenz | keine Änderungen auf allen Knoten. Nur der Funktionstest lädt bewusst ein neues Testartefakt hoch. |
| `ansible-lint` im Profil `production` und `yamllint` | keine Befunde im finalen Stand |
| Offline Bundle bauen | 6,2 GB mit 454 RPMs samt vollständiger Abhängigkeiten, 5 Images, der Collection und dem Projekt |
| Erstinstallation ohne Internet auf frischen VMs, Steuerknoten nur aus dem Bundle eingerichtet | erfolgreich in 9 Minuten 42 Sekunden, alle Komponenten gesund, siehe [09](09-offline.md) |
| zweiter Lauf ohne Internet | keine Änderungen, nachdem Fehler 12 behoben war |
| Rolling Update von Artifact Keeper per Playbook unter Last, Probe alle 0,5 Sekunden | keine Fehler bei 106 Anfragen, beide Backends nacheinander neu gestartet |
| Knoten mit VIP und Primary hart aus und wieder an | etwa 44 Sekunden Unterbrechung durch den Failover der Datenbank. Nach dem Booten kehrte der Knoten ohne Eingriff als Replica zurück, Quadlets und Patroni starten also korrekt. |

### Fehler, die erst bei der Automatisierung auffielen

Diese Punkte zeigten sich erst beim Test auf frischen VMs. Im von Hand aufgebauten Labor waren sie verdeckt. Alle sind in den Rollen behoben, und sie zeigen, warum ein Test von Grund auf wichtig ist.

| Nr. | Symptom | Ursache | Lösung in der Rolle |
|---|---|---|---|
| 1 | Ansible verliert nach der Firewall Task die Verbindung mit `No route to host`. | Die an das Clusternetz gebundene Zone `ak-cluster` gilt auch für SSH vom Steuerknoten, und dort war `ssh` nicht erlaubt. Im ersten Labor lief SSH über den NAT Adapter, deshalb fiel es dort nicht auf. | `base_firewall_services: [ssh]`, gesetzt bevor das Netz an die Zone gebunden wird |
| 2 | Das Backend startet nicht und meldet `AK_WEBHOOK_SECRET_KEY must decode to exactly 32 bytes`. | Artifact Keeper verlangt Base64 von genau 32 Byte. Die Dokumentation nennt dieses Format nicht. | Der Generator erzeugt Base64 aus 32 Byte, die Defaults der Rolle weisen darauf hin. |
| 3 | Bei einer Änderung am Template starten alle etcd Mitglieder gleichzeitig neu. | Handler laufen auf allen Hosts parallel. | `throttle: 1` und die Option `infrastructure_serial` |
| 4 | Das Warten auf etcd endet nie. | etcd liefert `/health` als `text/plain`. | Die Antwort wird ausdrücklich mit `from_json` ausgewertet. |
| 5 | Der zweite Funktionstest scheitert mit HTTP 409. | Artefakte sind in Artifact Keeper unveränderlich. | eindeutiger Pfad für jeden Lauf |
| 6 | `dnf download` bricht beim Bau des Bundles ab. | PGDG signiert seine Metadaten, und nur das dnf von root kennt den importierten Schlüssel. | Download mit `become` und `-y` |
| 7 | `ansible.posix.seboolean` braucht Python Bindings. | Die Minimal ISO enthält `python3-libsemanage` nicht. | Paket in `base_packages` aufgenommen |
| 8 | Die Version der Weboberfläche ist nicht festgelegt. | `latest` ist nicht reproduzierbar und offline unbrauchbar. | fest auf 1.11.2, das ist derselbe Digest wie das im Labor getestete `latest` |
| 9 | Ohne Internet lässt sich Podman nicht installieren, weil `passt` das Paket `passt-selinux` braucht. | `dnf download --resolve --alldeps` folgt keinen bedingten Abhängigkeiten wie `(passt-selinux if selinux-policy-targeted)`. | Das Bundle löst die Pakete über eine echte dnf Transaktion in ein leeres Installroot mit `@core` und allen Paketen auf. |
| 10 | Beim Bau des Bundles lassen sich die Metadaten von PGDG nicht laden. | Die URLs von PGDG enthalten `$releasever_minor`, das mit `--releasever 10` leer bleibt. | Übergabe der vollständigen Release 10.2 |
| 11 | Das Backend startet etwa jede Minute neu, und der Failover dauert 79 statt 44 Sekunden. | Ein `HealthCmd` in Quadlet als einfacher Text läuft über `/bin/sh -c`. Das Image enthält keine Shell, der Check schlägt also immer fehl, und `HealthOnFailure=kill` beendet den Container. | Exec Form `HealthCmd=["curl",...]` ohne äußere Anführungszeichen, weil Quadlet diese sonst wörtlich weitergibt |
| 12 | Der zweite Lauf ohne Internet meldet eine Änderung. | `tar` übernimmt Eigentümer und Rechte des Eintrags `./` aus dem Archiv. | `unarchive` mit `--no-same-owner` und `--no-overwrite-dir` |

## Ohne VirtualBox

Die Rollen enthalten nichts, was nur in VirtualBox funktioniert. Für andere Plattformen genügt es, `inventories/airgapped/` zu kopieren und anzupassen.

* Hostnamen, `ansible_host`, `ak_cluster_network`, `ak_vip` und `ansible_user` eintragen.
* `base_chrony_servers` auf interne NTP Server setzen. Ohne Zeitquelle laufen die Uhren auseinander, was etcd und Patroni stört.
* Die Netzwerkkarte wird automatisch über `ak_cluster_ip` erkannt.
* VRRP für die VIP muss erlaubt sein. Bei VMware sind dafür „MAC address changes“ und „Forged transmits“ an der Portgruppe nötig, bei Hyper V „MAC address spoofing“. In Public Clouds ist VRRP meist gesperrt, dort ersetzt ein Load Balancer der Cloud die Rolle `keepalived`.
* Die Podman Volumes liegen unter `/home/ak/.local/share/containers`, PostgreSQL unter `/var/lib/pgsql`. In der Produktion sollten dafür eigene Dateisysteme oder Logical Volumes vorgesehen werden.

## Grenzen

* Das Layout von Garage und die Mitgliedschaft in etcd werden nur beim ersten Aufbau gesetzt. Knoten hinzufügen oder ersetzen bleibt ein bewusster Schritt von Hand mit `garage layout assign`, `garage layout apply` und `etcdctl member add`.
* Geänderte Passwörter in `vault.yml` wirken bei PostgreSQL nur beim Bootstrap. Danach ist zusätzlich `ALTER ROLE` nötig.
* TLS am Frontend von HAProxy, das Security Plugin von OpenSearch und mTLS für etcd sind nicht automatisiert, siehe die Härtung im [Betriebshandbuch](07-betrieb.md).
* Die NFS Variante aus [04](04-hochverfuegbarkeit.md) ist nicht enthalten, empfohlen wird S3.
