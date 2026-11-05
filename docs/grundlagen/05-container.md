# 5 Container

[Zurück: Datendienste](04-datendienste.md) | [Übersicht Grundlagen](README.md) | [Weiter: Benutzer und Rechte](06-identitaeten.md)

## Container und Image

Ein **Image** enthält ein Programm mit allem, was es braucht. Ein **Container** ist ein laufender Prozess aus diesem Image, der vom restlichen System abgeschirmt ist. Anders als eine VM bringt er kein eigenes Betriebssystem mit, das macht ihn leicht und schnell. Ohne Weiteres gehen seine Daten beim Löschen verloren. Deshalb legt er sie in **Volumes** ab, die getrennt von ihm bestehen.

## Podman

**Podman** startet Container wie Docker, mit zwei Unterschieden, die hier zählen: Es braucht keinen dauernd laufenden Dienst, und es ist in Rocky Linux enthalten.

## Rootless

Rootless bedeutet: Der Container läuft unter einem normalen Benutzer, nicht unter `root`. Bricht jemand aus dem Container aus, erreicht er nur dieses Konto. Im Projekt heißt es `ak`, hat kein Passwort, kein sudo und keine Anmeldeshell.

Was bedeutet das im Alltag?

* Befehle laufen als dieser Benutzer. `sudo -u ak podman ps` funktioniert von `/` aus, weil der Benutzer sonst das aktuelle Verzeichnis nicht lesen darf. Dazu gehört die Variable `XDG_RUNTIME_DIR`.
* **Linger** sorgt dafür, dass die Dienste des Benutzers auch ohne Anmeldung laufen.
* Im Container hat ein Prozess zwar die Kennung `root`, draußen ist er aber ein unprivilegierter Nutzer aus einem eigenen Bereich von Kennungen (subuid).

## Quadlet und systemd

**systemd** startet in Linux alle Dienste, überwacht sie und startet sie bei Bedarf neu. **Quadlet** verbindet Podman damit: Eine kleine Datei beschreibt den Container, daraus erzeugt systemd einen normalen Dienst. Ein vereinfachtes Beispiel aus diesem Projekt:

```ini
[Container]
ContainerName=keycloak
Image=quay.io/keycloak/keycloak:26.1.4
Pull=never
PublishPort=8080:8080

[Service]
Restart=always

[Install]
WantedBy=default.target
```

Die Dateien liegen unter `/etc/containers/systemd/users/<uid>/`. Sie gehören `root`, der Benutzer `ak` darf sie also ausführen, aber nicht verändern. `Pull=never` verhindert, dass beim Start ungeplant eine neue Version geladen wird.

Dienste prüfen:

```bash
sudo -u ak XDG_RUNTIME_DIR=/run/user/$(id -u ak) systemctl --user status ak-backend
```

Podman startet einen Container nach einem Absturz neu, nicht aber, wenn ein Administrator ihn bewusst mit `podman stop` beendet hat. Das ist beim Testen zu beachten.

## SELinux

**SELinux** ist eine zusätzliche Schutzschicht in Rocky Linux. Selbst wenn die Dateirechte passen, darf ein Prozess nur, was seine Richtlinie erlaubt. Daher braucht ein Volume mit Dateien vom Host die Kennzeichnung `:Z`. Diese ordnet die Dateien dem Container zu. SELinux bleibt in diesem Projekt aktiv und wird nicht abgeschaltet. Fehlermeldungen mit `Permission denied` trotz passender Rechte deuten oft darauf hin:

```bash
sudo ausearch -m avc -ts recent
```

## Zusammenspiel im Projekt

| Dienst | Läuft als | Warum |
|---|---|---|
| Artifact Keeper, etcd, Garage, OpenSearch, Keycloak, JCR | rootless Container mit Quadlet | Abschottung, einfache Updates durch neue Images |
| PostgreSQL mit Patroni | systemd Dienst aus RPM Paketen | Datenbank unabhängig von der Container Umgebung |
| HAProxy, keepalived | systemd Dienst aus RPM Paketen | braucht Netzwerkrechte für die VIP |
