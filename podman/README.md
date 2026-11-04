# Artifact Keeper und JFrog Artifactory OSS mit rootless Podman auf Rocky Linux 10.2

Getestet am 3. November 2026 mit Rocky Linux 10.2, Podman 5.8.2 und podman-compose 1.5.0 aus EPEL, rootless als Benutzer `rocky`.

| Stack | Version | URL vom Windows-Host | Login |
|---|---|---|---|
| Artifact Keeper | 1.11.11 | http://localhost:30080 | `admin` mit `ADMIN_PASSWORD` aus `artifact-keeper/.env` in der VM |
| Artifactory OSS | 7.161.26 | http://localhost:8082 für die Oberfläche, :8081 direkt | `admin` mit `password`, beim ersten Login ändern |

## Einmalige Vorbereitung der VM

```bash
sudo dnf -y install epel-release && sudo dnf -y install podman podman-compose openssl jq
sudo firewall-cmd --permanent --add-port={30080,30443,8081,8082}/tcp && sudo firewall-cmd --reload
sudo loginctl enable-linger $USER                      # rootless Container auch ohne Login
systemctl --user enable --now podman-restart.service   # Autostart nach dem Booten (restart: always)
echo 'vm.max_map_count=262144' | sudo tee /etc/sysctl.d/90-opensearch.conf && sudo sysctl --system
```

## Start und Test

```bash
cd ~/podman/artifact-keeper && ./setup.sh   # erzeugt .env und TLS-Zertifikate für Postgres, startet den Stack
cd ~/podman/artifactory-oss && ./setup.sh
~/podman/test-artifact-keeper.sh            # Login, Repository, Upload, Download
~/podman/test-artifactory.sh                # Health, Ping, Upload, Download
```

## Anpassungen für Podman gegenüber den offiziellen Compose-Dateien

Für beide Stacks:

* `x-podman: in_pod: false`, weil podman-compose sonst alles in einen Pod packt.
* `restart: always`, denn nur solche Container startet `podman-restart.service` nach dem Booten.
* Keine Init-Container in `depends_on`. podman-compose macht daraus `--requires`, und Podman verweigert den Start, sobald der Init-Container beendet ist („container state improper“).
* Zugangsdaten ausschließlich über `.env` mit Pflichtprüfung `${VAR:?}`, keine fest eingetragenen Passwörter.
* Datenbank und OpenSearch werden nicht auf dem Host veröffentlicht.

Für Artifact Keeper:

* Statt `pg-certs` erzeugt `setup.sh` die Zertifikate. Den Eigentümer setzt `podman unshare chown 70:70`, eingebunden wird mit `:ro,Z`.
* Statt `scan-workspace-init` sorgt die Volume-Option `:U` dafür, dass Podman den Eigentümer auf die UID 1001 setzt.
* Dependency-Track liegt in `compose.dtrack.yaml`, weil podman-compose `required: false` nicht unterstützt.

Für Artifactory OSS:

* Benannte Volumes statt `external: true` und `config.sh`. Podman übernimmt die UID 1030 aus dem Image.
* Healthchecks und `service_healthy`, weil das Original nicht auf die Datenbank wartet.
* `ulimits.nproc` ist entfernt, weil rootless Container das harte Limit des Hosts nicht überschreiten dürfen. `logging: json-file` ist ebenfalls entfernt.
* Der Java-Heap lässt sich über `ARTIFACTORY_JAVA_OPTS` einstellen, Standard sind 2 GB. Für JCR statt OSS genügt `ARTIFACTORY_EDITION=artifactory-jcr`.
* Repositories lassen sich in OSS nicht per REST-API anlegen, das bleibt der Pro-Version vorbehalten. Der Weg führt über die Oberfläche.
