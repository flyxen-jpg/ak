# Ansible für den HA Cluster mit Artifact Keeper

Dieses Projekt installiert den in `../docs/` beschriebenen hochverfügbaren Aufbau auf frisch installierte Hosts mit Rocky Linux 10 oder RHEL 10 Minimal, wahlweise mit Internet oder vollständig ohne Netzverbindung nach außen. Die Kommentare im Code sind auf Englisch.

| Komponente | Wo | Wie |
|---|---|---|
| etcd 3.6 als DCS für Patroni | alle drei Knoten | rootless Podman mit Quadlet |
| Garage 2.5 als S3 mit drei Replikas | alle drei Knoten | rootless Podman mit Quadlet |
| OpenSearch 2.19 für die Suche | alle drei Knoten | rootless Podman mit Quadlet |
| PostgreSQL 18 mit Patroni | Knoten in `ak_app` | RPMs von PGDG, systemd |
| HAProxy und keepalived mit VIP | Knoten in `ak_app` | RPMs, systemd |
| Backend und Web von Artifact Keeper | Knoten in `ak_app` | rootless Podman mit Quadlet |

## Voraussetzungen

* Steuerknoten: Rocky Linux oder RHEL 10 mit `ansible-core` ab 2.16. Mehr ist nicht nötig, die Collections werden in `./collections` installiert.
* Zielknoten: Minimalinstallation, Zugang per SSH Schlüssel für einen Benutzer mit sudo ohne Passwort und eine statische IP im Clusternetz. Python 3 gehört zur Minimalinstallation.

## Schnellstart mit Internet

```bash
ansible-galaxy collection install -r requirements.yml -p collections
tools/generate-vault.py inventories/virtualbox-online/group_vars/all/vault.yml
export ANSIBLE_VAULT_PASSWORD_FILE=~/.ansible/ak-vault-pass
ansible-playbook -i inventories/virtualbox-online/hosts.yml playbooks/site.yml
```

## Einzelner Host mit reinem NAT

Artifact Keeper und auf Wunsch Artifactory OSS auf einer einzigen, von Hand installierten Rocky VM. Ansible läuft auf der VM selbst.

```bash
tools/generate-vault.py inventories/standalone/group_vars/all/vault.yml
ansible-playbook -i inventories/standalone/hosts.yml playbooks/standalone.yml -K
```

## Hochverfügbarkeit im NAT Netzwerk mit Management VM

Knoten von Hand installieren, alle im selben NAT Netzwerk von VirtualBox, dann von der Management VM aus:

```bash
tools/copy-ssh-keys.sh inventories/natnetwork/hosts.yml
ansible-playbook -i inventories/natnetwork/hosts.yml playbooks/bootstrap.yml -K
ansible-playbook -i inventories/natnetwork/hosts.yml playbooks/site.yml
ansible-playbook -i inventories/natnetwork/hosts.yml playbooks/artifactory.yml
```

## Migration aus Artifactory

```bash
ansible-playbook -i inventories/<umgebung>/hosts.yml playbooks/artifactory_seed.yml   # Testdaten für OSS, nur im Labor
ansible-playbook -i inventories/<umgebung>/hosts.yml playbooks/jcr_seed.yml           # Testdaten für JCR: Images, Charts, Gruppen, nur im Labor
ansible-playbook -i inventories/<umgebung>/hosts.yml playbooks/migrate.yml            # Artefakte, Prüfung, Rechte
ansible-playbook -i inventories/<umgebung>/hosts.yml playbooks/migrate.yml --tags verify_images,verify_access   # Digest und Zugriffsmatrix
```

## Keycloak und Nachweise

`playbooks/keycloak.yml` installiert einen Test Identitätsanbieter. `tools/evidence/` enthält die Skripte, mit denen sich die Befunde aus `../docs/12-rechte-und-identitaeten.md` nachstellen lassen.

## Ohne Internet

```bash
# 1. auf einem Rechner MIT Internet und derselben Release wie die Zielknoten
ansible-playbook playbooks/bundle.yml -e bundle_dir=/srv/ak-bundle
# 2. /srv/ak-bundle in das isolierte Netz bringen, dann auf dem Steuerknoten
tools/install-control-node.sh /srv/ak-bundle
ansible-playbook -i inventories/virtualbox-offline/hosts.yml playbooks/site.yml
```

Vorbereitung, Voraussetzungen und Testergebnis beschreibt `../docs/09-offline.md`.

## Aufbau

```text
ansible.cfg            Projekteinstellungen: kein Standard-Inventory, become je Task, Pipelining
requirements.yml       fest eingetragene Collections (ansible.posix)
inventories/
  virtualbox-online/   VirtualBox-Labor mit Internet
  virtualbox-offline/  VirtualBox-Labor ohne Internet, Installation aus dem Bundle
  airgapped/           Vorlage für beliebige Hypervisoren oder Bare Metal ohne Internet
  standalone/          ein Host, reines NAT, Ansible lokal auf dem Host
  natnetwork/          Hochverfügbarkeit im NAT-Netzwerk, gesteuert von einer Management-VM
playbooks/             site.yml ruft prepare, infrastructure, database, loadbalancer, artifact_keeper und verify auf
                       bundle.yml baut das Offline-Bundle
                       standalone.yml, bootstrap.yml, artifactory.yml, artifactory_seed.yml, migrate.yml
roles/                 eine Rolle je Komponente, Variablen mit dem Rollennamen als Präfix
tools/                 generate-vault.py, install-control-node.sh, copy-ssh-keys.sh
```

## Konventionen

Das Projekt folgt den [Ansible Best Practices von ATIX](https://atix.de/en/blog/ansible-best-practices/). Alle Module werden mit vollständigem Namen aufgerufen, jede Task hat einen Namen, und `become` steht an der einzelnen Task. Variablen einer Rolle beginnen mit deren Namen (`etcd_*`, `garage_*` und so weiter), Werte für die ganze Umgebung mit `ak_*`. Einstellbare Werte liegen in `defaults/`. Geheimnisse stehen nur verschlüsselt in `vault.yml` und werden über `secrets.yml` unter lesbaren Namen angesprochen. `import_*` hat Vorrang vor `include_*`. Jedes Template beginnt mit `ansible_managed` und dem Namen der erzeugenden Rolle. `command` und `shell` kommen nur zum Einsatz, wo es kein Modul gibt, und dann immer mit `changed_when` oder `creates`.

Geprüft wird mit `ansible-lint` im Profil `production` und mit `yamllint`. Die Konfiguration dafür liegt in diesem Verzeichnis.
