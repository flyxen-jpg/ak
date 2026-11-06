# 14 JFrog mit wenig Speicher und kurzen Wartezeiten

[Zurück: Airgap mit zwei VMs](13-airgap-zwei-vms.md) | [Übersicht](README.md)

Dieses Kapitel gilt für JFrog Container Registry (JCR) und Artifactory OSS in der Version 7.161.26 als Quelle einer Migration oder als Testsystem. Für ein Produktivsystem gelten andere Werte, siehe [Grenzen](#grenzen).

## Ergebnis

Gemessen auf einer VM mit 3 GB RAM, von denen 2691 MB nutzbar sind, 2 vCPU, Rocky Linux 10.2, mit 24 Images und 7 Gruppen als Datenbestand.

| Messwert | vorher | nachher | Änderung |
|---|---|---|---|
| Neustart, bis REST API und Registry antworten | 115 s | 79 bis 82 s | etwa 30 Prozent schneller |
| Neustart, bis die Anmeldung der Oberfläche antwortet | 299 s | 80 bis 83 s | **72 Prozent schneller** |
| Speicher aller JFrog Prozesse, belegt und ausgelagert | 3304 MB | 2205 bis 2215 MB | 33 Prozent weniger |
| Sauberes Beenden | Abbruch nach 10 s | 52 s, ohne Abbruch | Keine Sperrdatei mehr beim nächsten Start |
| Testdaten laden (24 Images, 5 Dateien, Gruppen und Rechte) | 431 s | 74 s | **fast sechsmal schneller** |

Die kurze Funktions- und Lastprobe lief danach nicht langsamer, sondern schneller, weil weniger ausgelagert wird:

| Probe | vorher | nachher |
|---|---|---|
| 20 MB hochladen | 0,88 s | 0,54 s |
| 40 Mal 20 MB herunterladen mit 8 Clients | 1,6 s | 1,3 s |
| 200 Metadatenabfragen mit 16 Clients | 1,8 s | 1,1 s |

Die Probe dauert nur Sekunden. Sie sagt nichts über Dauerlast, siehe [Grenzen](#grenzen).

## Was die Rolle jetzt tut

Die Werte stehen in `ansible/roles/artifactory_oss/defaults/main.yml` und sind über `artifactory_oss_small` schaltbar.

| Einstellung | Wert | Begründung |
|---|---|---|
| `JF_JFCONNECT_ENABLED` | `false` | beseitigt die 180 Sekunden Wartezeit der Anmeldung |
| `JF_SHARED_EXTRAJAVAOPTS` | `-Xms256m -Xmx640m`, G1 mit 2 und 1 Threads, Code Cache 96 MB, Direct Memory 128 MB | Heap von Artifactory |
| `JF_ACCESS_EXTRAJAVAOPTS` | `-Xms64m -Xmx192m -XX:+UseSerialGC` | Access nimmt sich sonst 25 Prozent des Speichers |
| `JF_JFBUS_EXTRAJAVAOPTS` | `-Xms32m -Xmx96m`, G1 mit 1 Thread | wie Access |
| `JF_TOPOLOGY_EXTRAJAVAOPTS`, `JF_JFCONFIG_EXTRAJAVAOPTS` | `-Xms32m -Xmx96m -XX:+UseSerialGC` | wie Access |
| alle JVMs | `-XX:TieredStopAtLevel=1 -Xss512k` | weniger Code Cache und kürzerer Start |
| `MALLOC_ARENA_MAX` | `2` | weniger Speicherarenen der C Bibliothek, Wert aus dem Sizing von JFrog |
| `StopTimeout` in der Quadlet Unit | `100` | Podman beendet den Container sonst nach 10 Sekunden hart |
| Warten in der Rolle | erst alle Dienste, dann REST API, dann Anmeldung, je 5 Sekunden Takt | Die Prüfung nur des Routers meldete zu früh Erfolg |

Die Rolle wartet mit kurzen Zeitlimits von 5 bis 8 Sekunden. Eine hängende Anfrage kostet damit keine 90 Sekunden mehr, die folgenden Schritte brauchen kein langes Zeitlimit.

## Drei Befunde, die in den Quellen nicht stehen

### Die Anmeldung wartet auf einen Dienst, den es nicht gibt

Nach jedem Start antwortete die Anmeldung konstant 180 Sekunden nach allen anderen Schnittstellen. Der Abstand blieb bei jeder Speichereinstellung gleich, Speichermangel schied damit aus.

So lässt sich die Ursache nachvollziehen:

1. Das Protokoll `frontend-service.log` zeigt im Sekundentakt `First-time entitlement fetch failed: 12 UNIMPLEMENTED: Received HTTP status code 404`.
2. Im Image liegt unter `/opt/jfrog/artifactory/app` kein Verzeichnis `jfconnect`. Der Dienst fehlt in dieser Edition, obwohl die Vorlage `system.full-template.yaml` ihn mit `enabled: true` führt.
3. Die Datei `node_modules/@jfrog/jfconnect-nodejs-client/dist/AbstractStore.js` im Frontend enthält `defaultConnectRetryTimeoutMs = 3 * 60 * 1000`. Das Frontend übergibt keinen anderen Wert.
4. Mit `JF_JFCONNECT_ENABLED=false` antwortet die Anmeldung 1 Sekunde nach der REST API.

Das hat nichts mit der fehlenden Internetverbindung zu tun, denn der Abruf geht an den lokalen Router. Im Labor mit Internet war die lange Antwortzeit der Oberfläche ebenfalls aufgefallen, siehe die Anmerkung in [Kapitel 11](11-nat-netzwerk.md).

### JFrog betreibt fünf JVMs, die Rolle begrenzte nur eine

Die verbreiteten Empfehlungen nennen nur `-Xmx`. Das betrifft aber allein Artifactory. Access, jfbus, Topology und JFConfig sind eigene Java Prozesse mit eigenen Schaltern. Vorher brauchten die fünf zusammen 2985 MB, davon allein Access 820 MB. Auf der VM mit 2691 MB lag dadurch mehr als 1 GB im Swap.

### SerialGC bricht den Start ab

Für kleine Systeme wird oft `-XX:+UseSerialGC` empfohlen. In `app/bin/artifactory.default` und `app/jfbus/bin/jfbus.sh` steht aber fest `-XX:+UseG1GC`. Zwei Collector verweigert die JVM, Artifactory startet dann nicht und meldet sich auch nach 420 Sekunden nicht. Die Rolle setzt SerialGC deshalb nur bei Access, Topology und JFConfig und begrenzt bei den anderen die Threads von G1.

## Messreihe

Jede Zeile ist ein Neustart mit demselben Datenbestand. Alle Zeiten in Sekunden ab dem Start der Unit. „Summe“ ist der Speicher aller Prozesse des Containers in MB, belegt und ausgelagert, gemessen 60 Sekunden nach dem Start.

| Profil | Änderung | Router | alle Dienste | REST API | Anmeldung | Summe |
|---|---|---:|---:|---:|---:|---:|
| `p0-alt` | Stand vorher, nur Artifactory begrenzt | 72,0 | 115,0 | 115,4 | 298,7 | 3304 |
| `p1-heap` | alle fünf JVMs begrenzt | 73,2 | 106,9 | 107,4 | 289,4 | 2591 |
| `p2-jvm` | dazu Code Cache, C1, Stack, Threads, `MALLOC_ARENA_MAX` | 50,7 | 83,9 | 84,1 | 265,8 | 2212 |
| `p3-pools` | dazu kleinere Thread und Datenbank Pools | 50,2 | 85,0 | 85,3 | 266,9 | 2223 |
| `p6-jfconnect` | `p2` und JFConnect aus | 50,2 | 83,5 | 83,7 | 84,6 | 2193 |
| `p7-final` | Rolle, erster Neustart | 48,9 | 78,9 | 79,2 | 80,1 | 2205 |
| `p8-final2` | Rolle, zweiter Neustart | 49,4 | 81,9 | 82,1 | 82,8 | 2215 |
| `p9-cds` | Rolle und AppCDS, drei Neustarts | 48,7 bis 50,1 | 82,1 bis 82,5 | 82,2 bis 82,7 | 82,9 bis 84,4 | 2212 bis 2240 |
| `oss-final` | Rolle mit Artifactory OSS, leerer Bestand | 50,1 | 87,1 | 87,3 | 88,0 | 2173 |

Diese Versuche brachten nichts oder schlugen fehl und sind deshalb nicht in der Rolle:

| Profil | Versuch | Ergebnis |
|---|---|---|
| `p3-pools` | Tomcat Threads 40 statt 200, Datenbankverbindungen 20 statt 100 | keine messbare Einsparung, Threads und Verbindungen entstehen erst bei Bedarf |
| `p4` und `p9` | AppCDS mit `-XX:+AutoCreateSharedArchive` | wirkungslos, auch nach sauberem Stopp entstand kein Archiv. Die Ursache wurde nicht weiter untersucht, das Verfahren ist also nicht widerlegt, sondern hier nicht in Betrieb gekommen. |
| `p5-services` | Topology, JFConfig und jfbus abgeschaltet | spart über 900 MB, aber JFrog wird nie bereit, Access, Event und Metadata bleiben ungesund, die API antwortet mit 503. Der Router führt diese Dienste als `required_service_types`. |
| `p10-min` | Artifactory 384 MB, Access 128 MB Heap | startet nicht, der Access Prozess fehlt nach dem Start |
| `Exec` Parameter für PostgreSQL | nicht nötig | PostgreSQL brauchte 52 bis 73 MB bei 18 bis 31 Verbindungen |

## Nachstellen

Das Skript misst auf der JFrog VM einen Start und schreibt eine Zeile nach `~/jfrog-measure.csv`. Die Profile sind Ergänzungen zur `artifactory.env` und werden danach zurückgesetzt.

```bash
cd ~/ansible
export RT_PASSWORD='<Administratorpasswort von JFrog>'
bash tools/evidence/jfrog-measure.sh p7-final restart
bash tools/evidence/jfrog-measure.sh p2-jvm restart "$PWD/tools/evidence/jfrog-profiles/p2-jvm.env"
```

Der Vergleich zum alten Zustand gelingt mit `artifactory_oss_small: false` im Inventory und einem weiteren Lauf der Rolle. Die Rohdaten aller Messungen liegen unter `lab/results/jfrog-tuning/`.

Zum Nachvollziehen der Ursache der Wartezeit:

```bash
sudo -u ak XDG_RUNTIME_DIR=/run/user/$(id -u ak) podman exec artifactory sh -c 'ls /opt/jfrog/artifactory/app; grep -c "First-time entitlement" /var/opt/jfrog/artifactory/log/frontend-service.log'
```

## Grenzen

* **Nur für Tests und Migrationen gedacht.** JFrog verlangt laut Dokumentation mindestens 4 CPU Kerne und 6 GB RAM für bis zu 20 aktive Clients, für Produktion 8 GB, für Tests nennt es 4 GB. Die Werte hier liegen darunter und sind von JFrog nicht unterstützt.
* **Dauerlast wurde nicht gemessen.** `-XX:TieredStopAtLevel=1` schaltet den optimierenden Compiler ab. Das spart Speicher und Startzeit und kostet unter längerer Last Durchsatz. Für eine große Migration empfiehlt sich `artifactory_oss_jvm_small: "-Xss512k"`.
* **JFConnect nur bei den freien Editionen abschalten.** Lizenzierte Editionen beziehen ihre Berechtigungen über JFConnect, ohne Internet über `jfconnect.airgap.enabled`. Das Abschalten wurde dort nicht geprüft, und `artifactory_oss_jfconnect_enabled` ist in diesem Fall auf `true` zu setzen.
* **Kein Spielraum nach unten.** Es bleiben rund 300 MB frei und 200 MB im Swap. 384 MB Heap starten nicht, Werte zwischen 384 und 640 MB wurden nicht geprüft. Unter einer VM mit 3 GB ist dieses Profil nicht getestet.
* **Große Bestände brauchen mehr.** Der Heap von 640 MB reichte für den Testbestand von 955 MB Daten. Bei vielen Millionen Dateien wächst der Bedarf.

## Quellen

| Quelle | Inhalt | Bewertung |
|---|---|---|
| [JFrog: Optimizing Artifactory JVM Settings](https://jfrog.com/help/r/artifactory-optimizing-artifactory-jvm-settings-best-practices/artifactory-optimizing-artifactory-jvm-settings-best-practices) | Heap, G1, `access.extraJavaOpts` | Grundlage, nennt aber die anderen JVMs nicht |
| [JFrog: General System Requirements](https://docs.jfrog.com/installation/docs/general-system-requirements) | Mindestwerte, Zeitabgleich | Die Seiten von JFrog widersprechen sich teilweise bei den Mindestwerten |
| [JFrog: System Requirements](https://docs.jfrog.com/installation/docs/system-requirements) | 4 GB für Tests, 8 GB für Produktion | wie oben |
| [JFrog: Java Requirements](https://docs.jfrog.com/installation/docs/java-requirements-for-jfrog-products) | mindestens 512 MB, OpenJDK 25 ab 7.161 | bestätigt |
| [JFrog: Artifactory System YAML](https://docs.jfrog.com/installation/docs/artifactory-system-yaml) | Schlüssel der Dienste und Pools | nennt keine Abhängigkeiten zwischen den Diensten |
| [JFrog Helm Chart, Größe small](https://raw.githubusercontent.com/jfrog/charts/master/stable/artifactory/sizing/artifactory-small.yaml) | `MALLOC_ARENA_MAX` und Java Schalter | Wert für die Arenen übernommen |
| [JFrog: Air Gapped Environment](https://docs.jfrog.com/installation/docs/configure-jfrog-platform-in-an-air-gapped-environment) | `jfconnect.airgap.enabled` | für lizenzierte Editionen |
| [JFrog: Allowlisted URLs](https://docs.jfrog.com/installation/docs/allowlisted-urls-and-air-gapped-environment-considerations) | Adressen, die JFrog sonst erreichen möchte | Grundlage der Prüfung ausgehender Verbindungen |
| [Microsoft: Java in Containern](https://learn.microsoft.com/is-is/azure/developer/java/containers/overview) | Hinweise zu SerialGC und Heap in Prozent | allgemein, für JFrog so nicht anwendbar |
| [Snapdeploy: Spring Boot in 512 MB](https://snapdeploy.dev/blog/spring-boot-512mb-container) | SerialGC, Code Cache, AppCDS | Einzelbeitrag, SerialGC und AppCDS brachten bei JFrog nichts |
