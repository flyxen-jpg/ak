# 02 Podman Deployment auf einem Einzelknoten

[Zurück: Laborumgebung](01-laborumgebung.md) | [Übersicht](README.md) | [Weiter: Migration](03-migration.md)

Beide Produkte liefern nur Compose Dateien für Docker aus. Die hier beschriebenen Varianten sind für rootless Podman 5.8 mit podman compose 1.5 aus EPEL unter SELinux im Modus enforcing angepasst. Getestet wurden sie auf Rocky Linux 10.2, sowohl funktional als auch mit einem Neustart der VM.

| Stack | Grundlage | Variante für Podman |
|---|---|---|
| Artifact Keeper 1.11.11 | [`docker-compose.yml` des Projekts](https://github.com/artifact-keeper/artifact-keeper/blob/main/docker-compose.yml) | [`podman/artifact-keeper/compose.yaml`](../podman/artifact-keeper/compose.yaml) |
| Artifactory OSS 7.161.26 | Bundle `jfrog-artifactory-oss-7.161.26-compose.tar.gz` von JFrog (`templates/docker-compose-volumes.yaml`) | [`podman/artifactory-oss/compose.yaml`](../podman/artifactory-oss/compose.yaml) |

## Vorbereitung des Hosts

```bash
sudo dnf -y install epel-release
sudo dnf -y install podman podman-compose openssl jq
sudo firewall-cmd --permanent --add-port={30080,30443,8081,8082}/tcp && sudo firewall-cmd --reload
sudo loginctl enable-linger "$USER"                      # rootless Container auch ohne angemeldete Sitzung
systemctl --user enable --now podman-restart.service      # Container mit restart=always nach dem Booten starten
echo 'vm.max_map_count=262144' | sudo tee /etc/sysctl.d/90-opensearch.conf && sudo sysctl --system
```

## Anpassungen an den offiziellen Compose Dateien

### Für beide Produkte

| Änderung | Grund |
|---|---|
| `x-podman: { in_pod: false }` | podman compose legt sonst alle Container in einen gemeinsamen Pod. Sie teilen sich dann den Netz Namespace, und es kommt zu Portkonflikten. |
| `restart: always` statt `unless-stopped` | `podman-restart.service` startet nach dem Booten nur Container mit `always`. |
| keine Init Container in `depends_on` | podman compose macht daraus `podman --requires`. Podman verweigert dann den Start, sobald der Init Container beendet ist (`container state improper`), und zwar bei jedem Neustart. |
| Zugangsdaten nur aus `.env` mit Pflichtprüfung `${VAR:?}` | keine fest eingetragenen Passwörter |
| Datenbank und OpenSearch nicht auf dem Host veröffentlicht | Erreichbar sind sie nur im Compose Netz. |
| Bind Mounts mit `:Z` | private SELinux Labels |

### Artifact Keeper

| Original | Variante für Podman |
|---|---|
| Der Init Container `pg-certs` erzeugt TLS Zertifikate. | `setup.sh` erzeugt sie auf dem Host, den Eigentümer setzt `podman unshare chown 70:70`. |
| Der Init Container `scan-workspace-init` ändert den Eigentümer eines Volumes. | Die Mount Option `:U` lässt Podman den Eigentümer auf den Container User 1001 setzen. |
| Dependency Track über ein Profil mit `required: false` | ausgelagert in `compose.dtrack.yaml`, weil podman compose `required: false` nicht kennt |

### Artifactory OSS

| Original | Variante für Podman |
|---|---|
| `config.sh` mit `ROOT_DATA_DIR` oder Volumes mit `external: true` | Compose legt benannte Volumes selbst an. Podman übernimmt dabei die UID 1030 aus dem Image. |
| kein Healthcheck, kein Warten auf die Datenbank | Healthchecks und `depends_on: service_healthy` |
| `ulimits.nproc: 65535` | entfernt, weil rootless Container das harte Limit des Hosts nicht überschreiten dürfen |
| `logging: json-file` | entfernt, Podman nutzt journald oder k8s file |
| Port `5432:5432` veröffentlicht | entfernt |
| fester Heap | über `ARTIFACTORY_JAVA_OPTS` einstellbar, im Labor `-Xms512m -Xmx1200m`. Die Ansible Rolle nutzt inzwischen das Profil aus [14](14-jfrog-tuning.md). |

## Start und Test

```bash
cd ~/podman/artifact-keeper && ./setup.sh     # .env und Zertifikate erzeugen, Stack starten
cd ~/podman/artifactory-oss && ./setup.sh
~/podman/test-artifact-keeper.sh               # Login, Repository, Upload, Download
~/podman/test-artifactory.sh                   # Health, Ping, Upload, Download
```

### Ergebnis

| Test | Artifact Keeper | Artifactory OSS |
|---|---|---|
| alle Container gesund | ja, 7 von 7 | ja, 2 von 2 |
| Login, Upload, Download | erfolgreich | erfolgreich |
| automatischer Start nach dem Booten | erfolgreich | erfolgreich |
| RAM im Leerlauf | Backend etwa 40 MB, insgesamt etwa 1,8 GB einschließlich OpenSearch | etwa 3,6 GB bei 2 GB Heap |

## Hinweise zu Artifactory OSS

* Die REST APIs zum Anlegen von Repositories, Usern, Gruppen und Berechtigungen sind in OSS gesperrt (`This REST API is available only in Artifactory Pro`). Die interne UI API unter `/ui/api/v1/` mit Session Login funktioniert dagegen, siehe `lab/artifactory/rtui.sh`. Sie ist nicht offiziell dokumentiert und kann sich mit jeder Version ändern.
* AQL (`/api/search/aql`) steht in OSS zur Verfügung. Darauf baut der Migrator von Artifact Keeper auf.
* Für die JFrog Container Registry genügt `ARTIFACTORY_EDITION=artifactory-jcr` in der `.env`.
