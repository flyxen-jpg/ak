# Evaluierung: Ablösung von JFrog Artifactory durch Artifact Keeper

Stand 4. November 2026. Geprüft mit Artifact Keeper 1.11.11, JFrog Container Registry und Artifactory OSS 7.161.26, Keycloak 26.1.4, Rocky Linux 10.2 und Podman 5.8.2.

## Auftrag und Ausgangslage

JFrog Artifactory ist lizenziert im Einsatz und soll abgelöst werden. Zu prüfen war, ob Artifact Keeper als Open Source Lösung diese Aufgabe übernehmen kann, also ob sie sich hochverfügbar betreiben lässt, ob der Bestand samt Benutzern und Gruppen umziehen kann und welche Risiken bleiben. Alle Aussagen wurden im Labor nachgestellt. Skripte und Rohdaten liegen in diesem Repository.

**Grenze der Prüfung:** Eine lizenzierte Instanz stand nicht zur Verfügung. Als Quelle dienten die kostenlosen Editionen JFrog Container Registry (JCR) für Container und Artifactory OSS für Maven. Merkmale der lizenzierten Editionen stammen aus der Dokumentation von JFrog.

## Ergebnis in Kürze

Artifact Keeper kann Artifactory ablösen, wenn Rechte auf Ebene der Repositories genügen und der Betrieb von PostgreSQL, S3 und OpenSearch abgedeckt ist. Der Datenbestand zieht zuverlässig um. Benutzer und Rechte brauchen ein eigenes Verfahren, das hier entwickelt und getestet wurde. Empfohlen wird ein Pilot mit einem Probelauf gegen eine Kopie der eigenen Instanz.

| Geprüft | Ergebnis |
|---|---|
| Produktionsimages mit festen Tags | 24 von 24 mit identischem Digest und vollständig ladbar, auch Multi Arch |
| Dateien aus Helm, Generic und Maven | 6 von 6 aus JCR, 449 von 449 aus OSS bitgenau |
| Ganze Benutzergruppen | 7 Gruppen mit 22 Benutzern exakt übernommen, per Playbook |
| Rechte gegen echte Zugriffe | 13 von 14 Fällen gleich, der Unterschied ist ein Pfadmuster und strenger als zuvor |
| Keycloak mit OpenID | funktioniert, wenn die Reihenfolge stimmt |
| Harter Ausfall eines Knotens | etwa 36 bis 44 Sekunden Unterbrechung, danach selbstständig wieder im Betrieb |
| Rolling Update | 0 Fehler |
| Installation | vollständig mit Ansible auf frischem Rocky Linux, online und offline |

## Fragen aus Sicht der Leitung

**Können wir aus dem Artifactory Vertrag aussteigen?**
Technisch spricht nichts dagegen, sofern keine Funktionen genutzt werden, für die es keinen Ersatz gibt, etwa Rechte auf Builds und Release Bundles, Federation oder Build Promotion. Das ist vor einer Kündigung für die eigene Nutzung zu prüfen. Die Lizenz sollte bis zum Ende der Rückfallfrist laufen. Siehe [06](06-bewertung.md).

**Was kostet es?**
Artifact Keeper steht unter MIT Lizenz, Lizenzkosten fallen nicht an. Es verschiebt die Kosten in den Betrieb: PostgreSQL, S3 und OpenSearch sind selbst zu betreiben oder von einer vorhandenen Plattform zu beziehen. Einen Preisvergleich enthält dieser Bericht nicht, weil die Vertragsdaten nicht vorlagen.

**Wer hilft uns, wenn es brennt?**
Es gibt keinen Herstellersupport mit SLA, nur die Community auf GitHub. Das ist das größte nicht technische Risiko. Gegenmaßnahmen sind eigenes Betriebswissen, das diese Dokumentation unterstützt, oder ein Wartungsvertrag mit einem Dienstleister.

**Wie reif ist das Produkt?**
Technisch solide, aber jung. Version 1.11 mit teils mehreren Releases pro Woche, Dokumentation stellenweise falsch. Versionen sind fest einzutragen, Updates laufen über eine Staging Umgebung.

**Gibt es beim Umzug einen Ausfall?**
Nur einen kurzen Schreibstopp bei der Umstellung. Der Bestand wird im laufenden Betrieb kopiert und mit Delta Läufen nachgezogen. Lesen bleibt durchgehend möglich. Siehe [03](03-migration.md).

**Können wir zurück, wenn es schiefgeht?**
Ja, solange Artifactory parallel nur lesend weiterläuft. Rückwärts migriert wird nicht, in der Zwischenzeit neu hochgeladene Artefakte wären von Hand zurückzuführen.

**Was geht beim Umzug verloren?**
Properties, Löschungen, der Inhalt von Remote Caches, Passwörter und Tokens. Pfadmuster in Rechten lassen sich nicht abbilden. Alle Pipelines brauchen neue Zugangsdaten und neue Adressen.

**Warum überhaupt Hochverfügbarkeit, und was ist sie wert?**
Bei JFrog ist sie laut Dokumentation der Enterprise Ausgabe vorbehalten. Im Test überstand das System den Ausfall eines ganzen Knotens nach etwa 36 bis 44 Sekunden ohne Eingriff.

**Was empfehlen Sie?**
Einen Pilot für ein Team mit Docker und Helm, einen Probelauf gegen eine Kopie der eigenen Instanz und erst danach die Entscheidung über den Vertrag.

## Fragen aus Sicht des Betriebs

**Was muss ich aufbauen?**
Mindestens drei VMs für den Cluster und eine Management VM. Die Knoten brauchen im Labor 2,5 bis 3,5 GB RAM, ein Produktivsystem deutlich mehr. Schritt für Schritt in [11](11-nat-netzwerk.md).

**Muss das in VirtualBox laufen? Brauche ich PowerShell?**
Nein. Ein von Hand installiertes Rocky Linux 10 Minimal und Ansible genügen. VirtualBox und die PowerShell Skripte unter `vm/` waren nur das Testlabor.

**Geht das ohne Internet?**
Ja, über ein Offline Bundle. Siehe [09](09-offline.md).

**Wie sicher sind unsere Images nach dem Umzug?**
Der Vergleich ist unabhängig vom Migrator. Der Digest jedes Manifests wird auf beiden Seiten verglichen, danach wird jedes Image komplett aus dem Ziel geladen. `playbooks/migrate.yml --tags verify_images` wiederholt das jederzeit.

**Warum überträgt die eingebaute Migration keine Gruppen, obwohl die Doku es sagt?**
Der Code wird nie aufgerufen und wäre auch nicht lauffähig. Der Bericht belegt das mit Dateinamen und Zeilen und einem Skript zum Nachstellen. Siehe [12](12-rechte-und-identitaeten.md).

**Wie bekomme ich ganze Gruppen trotzdem rüber?**
`playbooks/migrate.yml --tags security`. Benutzer erhalten ein Einmalpasswort, Gruppen ihre Mitglieder, Rechte werden zu Regeln. Wiederholte Läufe folgen der Quelle.

**Was ist anders am Rechtemodell?**
Artifactory hat Permission Targets mit Pfadmustern, Artifact Keeper einfache Regeln je Repository. Ein Team, das heute nur einen Pfad sehen darf, braucht künftig ein eigenes Repository. Vergleich in [12](12-rechte-und-identitaeten.md).

**Wir nutzen Keycloak oder ein anderes Verzeichnis. Was passiert mit den Identitäten?**
Sie werden nicht übernommen, sondern neu angebunden. Wichtig ist die Reihenfolge: Ein migriertes lokales Konto blockiert die Anmeldung mit HTTP 409, eine migrierte Gruppe gleichen Namens bleibt leer. Der funktionierende Ablauf steht in [12](12-rechte-und-identitaeten.md).

**Greift der Entzug von Rechten sofort?**
Nein. Wird jemand in Keycloak aus einer Gruppe entfernt, wirkt das erst bei der nächsten Anmeldung. Vorhandene API Tokens funktionieren bis dahin weiter, das wurde getestet. Der Austrittsprozess muss das Konto daher auch in Artifact Keeper deaktivieren.

**Was passiert mit unseren Pipelines?**
Sie brauchen neue Tokens und die neue Adresse. Technische Konten bleiben lokal, ihre Tokens stellt ein Administrator aus, denn bei aktivem Identitätsanbieter können sie sich nicht mehr anmelden. Die in `AK_EXTERNAL_URL` eingetragene Adresse muss von allen Clients erreichbar sein, sonst scheitert `docker login`.

**Wie groß ist der Aufwand im täglichen Betrieb?**
Status, Updates, Backup und Fehlersuche stehen in [07](07-betrieb.md). Updates laufen als Rolling Update per Playbook.

**Ich kenne keepalived, VIP und Quorum nicht. Wo fange ich an?**
Im Ordner [Grundlagen](grundlagen/README.md). Er setzt kein Vorwissen voraus und erklärt auch den Aufbau der Ansible Skripte.

## Wichtigste Erkenntnisse

1. Benutzer, Gruppen und Rechte migriert Artifact Keeper 1.11.11 nicht, entgegen seiner Dokumentation.
2. Lokale Konten und Identitätsanbieter lassen sich nicht verknüpfen. Die Reihenfolge der Einführung entscheidet.
3. Docker Repositories werden entgegen der Dokumentation automatisch und vollständig migriert. Der Remote Cache wird nicht übertragen.
4. Das Rechtemodell kennt keine Pfadmuster.
5. Die Suchindizes entstehen ohne Replikas, ein Index Template behebt das.
6. Während eines Datenbankwechsels antwortet Artifact Keeper teilweise mit 401 statt 503.
7. Die REST API für Downloads ist bei S3 auf 30 Anfragen pro Minute und Adresse begrenzt, die nativen Endpunkte nicht.
8. MinIO liefert keine Community Images mehr, als S3 Speicher dient deshalb Garage.
9. Erst die Automatisierung auf frischen VMs brachte weitere Fehler ans Licht. Die Liste steht in [08](08-ansible.md).

## Inhalt

| Dokument | Inhalt |
|---|---|
| [Grundlagen](grundlagen/README.md) | Einführung ohne Vorwissen: Netzwerk, Hochverfügbarkeit, Datendienste, Container, Identitäten, Ansible |
| [01 Laborumgebung](01-laborumgebung.md) | VirtualBox, Rocky Linux, Netzwerk, Ressourcen |
| [02 Podman Deployment](02-podman-deployment.md) | Compose Dateien und Anpassungen für Podman auf einem Einzelknoten |
| [03 Migration](03-migration.md) | Container und Dateien, Delta Läufe, Prüfung, Lücken, Migrationswege |
| [04 Hochverfügbarkeit](04-hochverfuegbarkeit.md) | Architektur und Konfiguration des Clusters |
| [05 Testprotokoll](05-testprotokoll.md) | Zehn Ausfallszenarien unter Last mit Messwerten |
| [06 Bewertung](06-bewertung.md) | Funktionsvergleich, Reifegrad, Risiken, Empfehlung |
| [07 Betriebshandbuch](07-betrieb.md) | Status, Wartung, Updates, Backup, Überwachung, Fehlersuche |
| [08 Ansible](08-ansible.md) | Automatisierte Installation, Rollen, Best Practices |
| [09 Offline Installation](09-offline.md) | Bundle und Ablauf ohne Internet |
| [10 Einzelknoten](10-einzelknoten.md) | Installation auf einer einzelnen Rocky VM |
| [11 NAT Netzwerk](11-nat-netzwerk.md) | Hochverfügbarkeit auf von Hand installierten VMs mit Management VM |
| [12 Rechte und Identitäten](12-rechte-und-identitaeten.md) | Warum Gruppen und Rechte nicht migriert werden, Modellvergleich, Keycloak, Nachstellen |

## Aufbau des Repositorys

```text
docs/        diese Dokumentation
ansible/     Ansible Projekt für Cluster, Quelle, Migration und Keycloak (siehe ansible/README.md)
  tools/evidence/  Skripte, die die Befunde aus Kapitel 12 nachstellen
podman/      Compose Dateien für einen Einzelknoten und Testskripte
lab/         Skripte der ersten Testphase und Rohdaten unter lab/results/
vm/          Labor Skripte für den Windows Host, für die Lösung nicht erforderlich
upstream/    unveränderte Originaldateien zum Vergleich
```

Zugangsdaten gehören nicht ins Repository und sind per `.gitignore` ausgeschlossen. Das betrifft `lab/ha/secrets.env`, `lab/ha/s3.env`, `vm/id_ed25519*`, `vm/credentials.txt`, die Datei `vault.yml` der Inventories und die Vault Passwortdatei `~/.ansible/ak-vault-pass`.
