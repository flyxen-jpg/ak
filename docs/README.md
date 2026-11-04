# Artifact Keeper als Ersatz für JFrog Artifactory

Stand 4. November 2026. Getestet mit Artifact Keeper 1.11.11, Artifactory OSS 7.161.26, Rocky Linux 10.2 und Podman 5.8.2.
Alle Aussagen wurden im Labor nachgestellt. Skripte und Rohdaten liegen in diesem Repository.

## Ergebnis

| Frage | Antwort |
|---|---|
| Lässt sich Artifact Keeper mit Podman betreiben? | Ja. Die offiziellen Compose-Dateien wurden für rootless Podman und SELinux angepasst und überstehen einen Neustart. Details in [02](02-podman-deployment.md). |
| Funktioniert die Live-Migration aus Artifactory? | Für Artefakte ja. Ein Voll-Lauf im laufenden Betrieb und anschließende Delta-Läufe übertrugen 449 von 449 Dateien bitgenau. User, Gruppen und Rechte werden trotz anderslautender Dokumentation nicht migriert, dafür entstand ein eigenes Skript. Gradle-Repositories, Mitglieder virtueller Repositories und Löschungen fehlen ebenfalls. Details in [03](03-migration.md). |
| Ist Artifact Keeper hochverfügbar betreibbar? | Ja, aktiv/aktiv mit HAProxy, keepalived, Patroni, etcd, Garage als S3 und OpenSearch. Artifactory bietet Hochverfügbarkeit nur mit Enterprise-Lizenz. Details in [04](04-hochverfuegbarkeit.md). |
| Wie verhält sich der Cluster bei Ausfällen? | Alle zehn Szenarien heilten sich selbst. Ein Rolling Update lief ohne Fehler, der Ausfall eines S3- oder Quorum-Knotens ebenfalls. Fällt ein ganzer Knoten aus, dauert die Unterbrechung etwa 36 Sekunden, bestimmt durch den Datenbank-Failover. Details in [05](05-testprotokoll.md). |
| S3 oder NFS? | S3 mit Garage, Ceph oder Cloud-Speicher. NFS funktioniert, macht den NFS-Server aber zum Single Point of Failure. Details in [04](04-hochverfuegbarkeit.md). |
| Lässt sich das automatisieren, auch ohne Internet? | Ja. Ein Ansible-Projekt nach den ATIX-Empfehlungen installiert den ganzen Cluster auf frische Rocky-10-Minimal-VMs. Getestet wurde online und vollständig offline über ein Bundle. Ein zweiter Lauf ändert nichts, ein Rolling Update per Playbook lief ohne Fehler. ansible-lint im Profil production meldet keine Befunde. Details in [08](08-ansible.md) und [09](09-offline.md). |
| Geht das auch ohne PowerShell und ohne besonderes Netz? | Ja. Auf von Hand installierten Rocky-VMs mit reinem NAT (Einzelknoten) oder im NAT-Netzwerk von VirtualBox mit einer Management-VM (Hochverfügbarkeit). Details in [10](10-einzelknoten.md) und [11](11-nat-netzwerk.md). |
| Welche Migrationswege gibt es? | API, Assistent in der Oberfläche, Pull-Through über ein Remote-Repository und manuell mit Maven funktionieren. k migrate taugt nur zwischen zwei Artifact-Keeper-Instanzen. Benutzer, Gruppen und Rechte überträgt keiner der eingebauten Wege, auch nicht der Assistent, obwohl er die Häkchen dafür anbietet. Details in [03](03-migration.md). |
| Taugt Artifact Keeper für den professionellen Alltag? | Ja, mit Einschränkungen. Technisch ist das Produkt solide und sparsam im Ressourcenbedarf. Einzuplanen sind die fehlende Migration der Berechtigungen, das gröbere Rechtemodell und ein junges Projekt mit hohem Release-Tempo ohne Herstellersupport. Details in [06](06-bewertung.md). |

## Inhalt

| Dokument | Inhalt |
|---|---|
| [01 Laborumgebung](01-laborumgebung.md) | VirtualBox, Rocky Linux, Netzwerk, Ressourcen, Stolperfallen |
| [02 Podman-Deployment](02-podman-deployment.md) | Offizielle Compose-Dateien und Anpassungen für Podman auf einem Einzelknoten |
| [03 Migration](03-migration.md) | Live-Migration, Delta-Läufe, Verifikation, Migration der Berechtigungen, Lücken |
| [04 Hochverfügbarkeit](04-hochverfuegbarkeit.md) | Architektur und Konfiguration von HAProxy, keepalived, Patroni, etcd, Garage und OpenSearch |
| [05 Testprotokoll](05-testprotokoll.md) | Zehn Ausfallszenarien unter Last mit Messwerten |
| [06 Bewertung](06-bewertung.md) | Funktionsvergleich, Reifegrad, Risiken, Empfehlung |
| [07 Betriebshandbuch](07-betrieb.md) | Status, Wartung, Updates, Backup, Monitoring, Fehlersuche |
| [08 Ansible](08-ansible.md) | Automatisierte Installation, Rollen, Umsetzung der Best Practices, Testergebnisse |
| [09 Offline-Installation](09-offline.md) | Bundle, Vorbereitung und Ablauf ohne Internet, in VirtualBox und auf anderer Infrastruktur |
| [10 Einzelknoten](10-einzelknoten.md) | Artifact Keeper und Artifactory auf einer schlichten Rocky-VM mit reinem NAT, Ansible auf der VM selbst |
| [11 NAT-Netzwerk](11-nat-netzwerk.md) | Hochverfügbarkeitssystem auf von Hand installierten VMs im NAT-Netzwerk, gesteuert von einer Management-VM |

## Wichtigste Erkenntnisse

1. Artifact Keeper 1.11.11 migriert keine Berechtigungen. Die Funktionen `migrate_users`, `migrate_groups` und `migrate_permissions` werden nie aufgerufen, das Kommandozeilenwerkzeug enthält an dieser Stelle ein `TODO`.
2. Die Suchindizes werden ohne Replikas angelegt. Fällt ein Knoten aus, steht die Suche nicht mehr vollständig zur Verfügung. Ein Index-Template behebt das.
3. Während eines Datenbank-Failovers antwortet Artifact Keeper teilweise mit 401 statt 503.
4. Die REST-API für Downloads ist bei S3 auf 30 Anfragen pro Minute und IP begrenzt. Die nativen Endpunkte der Paketformate sind davon nicht betroffen.
5. Das Rechtemodell kennt keine Pfadmuster. Ausschlüsse aus Artifactory lassen sich nicht abbilden.
6. MinIO liefert keine Community-Images mehr. Als S3-Speicher dient deshalb Garage.
7. Artifactory OSS sperrt die REST-APIs für Repositories, User und Rechte. Sie sind der Pro-Version vorbehalten.
8. Properties aus Artifactory (	eam, uild.number und ähnliche) gehen bei der Migration verloren.
9. Erst die Automatisierung auf frischen VMs brachte weitere Fehler ans Licht, darunter eine Firewall-Zone, die SSH sperrt, Schlüssel, die exakt 32 Byte lang sein müssen, ein Container-Healthcheck, der ohne Shell nicht läuft, und ein Offline-Bundle ohne bedingte RPM-Abhängigkeiten. Die Liste steht in [08](08-ansible.md).

## Aufbau des Repositorys

```text
docs/        diese Dokumentation
ansible/     Ansible-Projekt für den HA-Cluster, online und offline (siehe ansible/README.md)
podman/      Compose-Dateien für Podman auf einem Einzelknoten (Artifact Keeper, Artifactory OSS) und Testskripte
lab/
  artifactory/   Befüllung von Artifactory (Testdaten, Helfer für die UI-API)
  migration/     Live-Migration, Verifikation, Migration der Berechtigungen, Rechtetest
  ha/            HA-Aufbau per Shell (etcd, Garage, OpenSearch, Patroni, HAProxy, keepalived, Artifact Keeper, NFS)
  results/       Rohdaten der Tests (CSV und Logs)
vm/          Skripte für VirtualBox, SSH und Tests auf dem Windows-Host (unter anderem create-node.ps1, ansible-run.ps1)
upstream/    unveränderte Original-Compose-Dateien zum Vergleich
```

Zugangsdaten gehören nicht ins Repository und sind per `.gitignore` ausgeschlossen. Das betrifft `lab/ha/secrets.env`, `lab/ha/s3.env`, `vm/id_ed25519*`, `vm/credentials.txt`, die Datei `vault.yml` der Labor-Inventories unter `ansible/inventories/` und die Vault-Passwortdatei `~/.ansible/ak-vault-pass`.
