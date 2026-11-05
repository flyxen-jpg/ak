# 10 Einzelknoten auf einer schlichten Rocky Installation mit NAT

[Zurück: Offline Installation](09-offline.md) | [Übersicht](README.md) | [Weiter: Hochverfügbarkeit im NAT Netzwerk](11-nat-netzwerk.md)

Dieses Szenario braucht keine Vorbereitung per PowerShell und kein besonderes Netzwerk. Rocky Linux wird von Hand aus der Minimal ISO installiert, die VM hat als einzige Netzwerkkarte „NAT“. Ansible läuft direkt auf dieser VM und richtet Artifact Keeper und auf Wunsch Artifactory OSS als Migrationsquelle ein. Es ist der schnellste Weg zu einer funktionierenden Testinstallation und zugleich die Grundlage, um eine Migration auszuprobieren.

## Warum die bisherigen Compose Dateien auf anderen Rechnern Probleme machen können

Die Compose Dateien aus [02](02-podman-deployment.md) funktionieren im Labor, setzen aber einiges stillschweigend voraus. Typische Fehlerquellen auf einem anderen Rechner sind:

* `podman-compose` kommt aus EPEL und verhält sich je nach Version unterschiedlich, etwa bei `depends_on` oder Init Containern.
* Die Versionen standen auf `latest`. Ein neues Release von Artifact Keeper konnte die Installation von einem Tag auf den anderen verändern.
* Skripte, die unter Windows bearbeitet oder kopiert wurden, haben Zeilenenden im Windows Format und brechen mit `bad interpreter` ab.
* Zu wenig Arbeitsspeicher führt zu Abbrüchen von OpenSearch oder Artifactory, die schwer zuzuordnen sind.
* Ohne Internetzugang oder DNS scheitert das Laden der Images mit wenig hilfreichen Meldungen.
* Der Zugriff von außen ist bei reinem NAT nur über eine Portweiterleitung möglich.

Die Ansible Variante beseitigt diese Punkte. Sie nutzt Quadlet statt podman compose, alle Versionen sind fest eingetragen, und eine Vorabprüfung bricht mit einer verständlichen Meldung ab, wenn Arbeitsspeicher, CPU, Plattenplatz, cgroup v2 oder die Erreichbarkeit der Registries nicht passen.

## Voraussetzungen

| | Wert |
|---|---|
| Betriebssystem | Rocky Linux 10 Minimal, von Hand installiert, Administratorkonto mit sudo |
| Netzwerk | eine Karte im Modus „NAT“, Internetzugang darüber |
| Arbeitsspeicher | mindestens 7 GB mit Artifactory, 3,5 GB nur für Artifact Keeper (im Test 8 GB) |
| CPU | mindestens 2 vCPU (im Test 4) |
| Platte | mindestens 25 GB frei unter `/home` (im Test 60 GB) |

## Ablauf

Alle Befehle laufen auf der VM selbst.

```bash
sudo dnf -y install ansible-core git
git clone <repository> && cd <repository>/ansible
ansible-galaxy collection install -r requirements.yml -p collections
tools/generate-vault.py inventories/standalone/group_vars/all/vault.yml
export ANSIBLE_VAULT_PASSWORD_FILE=~/.ansible/ak-vault-pass
ansible-playbook -i inventories/standalone/hosts.yml playbooks/standalone.yml -K
```

`-K` fragt das sudo Passwort des Administratorkontos ab. Die Passwörter für die Anmeldung als `admin` an beiden Oberflächen stehen danach im Vault (`ansible-vault view inventories/standalone/group_vars/all/vault.yml`).

Wer nur Artifact Keeper möchte, setzt `standalone_artifactory_enabled: false` in `inventories/standalone/group_vars/all/main.yml`.

## Zugriff vom Host bei reinem NAT

Bei NAT ist die VM vom Host nur über eine Portweiterleitung erreichbar. In VirtualBox unter Einstellungen, Netzwerk, Erweitert, Port Weiterleitung zwei Regeln anlegen:

| Name | Host Port | Gast Port |
|---|---|---|
| Artifact Keeper | 30080 | 30080 |
| Artifactory | 8082 | 8082 |

Danach sind die Oberflächen auf dem Host unter `http://localhost:30080` und `http://localhost:8082` erreichbar. Im Test funktionierte das ohne weitere Einstellungen.

## Was installiert wird

| Komponente | Umsetzung |
|---|---|
| Artifact Keeper | PostgreSQL 18.6, OpenSearch 2.19.6, Backend 1.11.11, Weboberfläche 1.11.2 und Caddy 2.11.7 als Reverse Proxy, jeweils als Quadlet Unit des Dienstkontos `ak` in einem eigenen Container Netz. Nur Caddy veröffentlicht einen Port (30080). |
| Artifactory OSS | PostgreSQL 17.10 und Artifactory 7.161.26 als Quadlet Units in einem eigenen Container Netz mit fester Adresse für Artifactory. Das Standardpasswort von `admin` wird beim ersten Start ersetzt. |
| Verbindung für die Migration | Das Backend von Artifact Keeper hängt zusätzlich im Netz von Artifactory. Der SSRF Schutz erlaubt genau die Adresse von Artifactory und sonst keine private Adresse. |

Die optionalen Scanner von Artifact Keeper (Trivy, OpenSCAP, Dependency Track) sind nicht enthalten. Sie brauchen mehrere Gigabyte zusätzlichen Arbeitsspeicher und sind für die Bewertung der Migration nicht nötig.

## Migration auf dem Einzelknoten

```bash
ansible-playbook -i inventories/standalone/hosts.yml playbooks/artifactory_seed.yml   # Testdaten, nur im Labor
ansible-playbook -i inventories/standalone/hosts.yml playbooks/migrate.yml            # Artefakte, Prüfung, Rechte
```

Die Migrationswege und ihre Ergebnisse stehen in [03](03-migration.md).

## Testergebnis

Getestet am 4. November 2026 auf einer VM mit 8 GB RAM und 4 vCPU, einzige Netzwerkkarte NAT, Rocky Linux 10.2 Minimal.

| Test | Ergebnis |
|---|---|
| Installation von Artifact Keeper und Artifactory per Playbook | erfolgreich, beide Oberflächen vom Host über die Portweiterleitung erreichbar |
| zweiter Lauf | keine Änderungen |
| Neustart der VM | alle sieben Container von selbst wieder gesund, Artifact Keeper meldet `ready`, Artifactory `HEALTHY` |
| Testdaten in Artifactory per Playbook | sechs Repositories, 57 Dateien, gefüllter Remote Cache, drei Benutzer, zwei Gruppen, zwei Permission Targets |
| Migration der Artefakte per Playbook | 59 Einträge mit 26 MB übertragen, Gradle Repository wie erwartet nicht migrierbar |
| Prüfung per SHA-256 | 58 von 58 Dateien identisch, nach einem Delta Lauf 59 von 59 |
| Migration der Rechte per Playbook | drei Benutzer mit Einmalpasswort, zwei Gruppen mit Mitgliedern, vier Regeln. Eine Regel mit Pfadausschluss und drei Regeln für das Gradle Repository wurden begründet ausgelassen. |
| Durchsetzung der übertragenen Rechte | alle Fälle wie in Artifactory, nur das allgemeine Leserecht über die Gruppe `readers` fehlt erwartungsgemäß |
| zweiter Lauf der Migration | inkrementeller Job, neue Benutzer und Gruppen nachgezogen, keine doppelten Regeln |

### Fehler, die dieser Test aufgedeckt hat

| Symptom | Ursache | Lösung |
|---|---|---|
| Wechsel des Admin Passworts von Artifactory schlägt fehl | Die Access API von Artifactory OSS lehnt Basic Auth ab | `POST /artifactory/api/security/users/authorization/changePassword` |
| Prüfung des Passworts meldet immer Erfolg | Anonymer Lesezugriff beantwortet die meisten Aufrufe unabhängig vom Passwort | Prüfung über `/artifactory/api/storageinfo`, das Administratorrechte verlangt |
| Anmeldungen an der UI API hängen sporadisch | Der Frontend Dienst von Artifactory OSS fragt jede Sekunde vergeblich Lizenzinformationen ab | kürzere Timeouts mit Wiederholung, „existiert bereits“ gilt als Erfolg |
| Hochladen von POM Dateien wird abgelehnt (409) | Artifactory prüft POMs auf gültiges XML | Testdaten erzeugen echte, minimale POMs |
| Repository Liste von Artifactory liefert 401 | Neue Installationen erlauben keinen anonymen Zugriff | Anmeldedaten bei jedem Aufruf |
| inkrementeller Lauf endet mit „failed“ | Ein Gradle Repository in der Auswahl lässt Jobs ohne neue Dateien scheitern | nicht migrierbare Typen werden vorab erkannt, ausgelassen und gemeldet |
