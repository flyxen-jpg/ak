# 11 Hochverfügbarkeit im NAT Netzwerk mit Management VM

[Zurück: Einzelknoten](10-einzelknoten.md) | [Übersicht](README.md)

Dieses Kapitel beschreibt den Aufbau des Hochverfügbarkeitssystems aus [04](04-hochverfuegbarkeit.md) so, wie er auf jedem Rechner reproduzierbar ist: Rocky Linux wird auf jeder VM von Hand und ohne Nacharbeit installiert, alle VMs hängen nur an einem gemeinsamen NAT Netzwerk von VirtualBox, und eine kleine Management VM richtet mit Ansible alles Weitere ein. PowerShell, Bridged- oder Host Only Adapter werden nicht gebraucht.

## Warum ein NAT Netzwerk und nicht einfaches NAT

VirtualBox kennt zwei NAT Varianten. Beim einfachen „NAT“ bekommt jede VM ein eigenes, isoliertes Netz. Die VMs erreichen das Internet, aber nicht einander, und ein Cluster ist damit unmöglich. Ein „NAT Netzwerk“ verbindet mehrere VMs in einem gemeinsamen Netz mit DHCP und Internetzugang. Für den Cluster ist das genau richtig, und es bleibt bei NAT ohne Bridged oder Host Only.

## Aufbau

| VM | RAM im Test | Aufgabe |
|---|---|---|
| ak-mgmt | 1 GB, mit Keycloak 2 GB | Management VM mit Ansible, optional Keycloak |
| ak-ha1 | 2,5 GB | Artifact Keeper, PostgreSQL mit Patroni, HAProxy, keepalived, etcd, Garage, OpenSearch |
| ak-ha2 | 2,5 GB | wie ak-ha1 |
| ak-ha3 | 3,5 GB | dritte Stimme für etcd, Garage und OpenSearch, dazu JFrog Container Registry als Quelle der Migration. 3,5 GB sind knapp, die Oberfläche der Quelle hängt dann zeitweise. |

Alle VMs hängen am NAT Netzwerk `ak-natnet` mit dem Bereich 10.0.10.0/24. Die VIP liegt auf 10.0.10.250.

## Schritt 1: NAT Netzwerk in VirtualBox anlegen

In VirtualBox unter Datei, Werkzeuge, Netzwerk Manager, Reiter NAT Netzwerke ein neues Netz anlegen: Name `ak-natnet`, IPv4 Präfix `10.0.10.0/24`, DHCP aktiviert. Bei jeder VM unter Einstellungen, Netzwerk den Adapter 1 auf „NAT Netzwerk“ und `ak-natnet` stellen. Weitere Adapter werden nicht gebraucht.

Damit der Host die Oberflächen erreicht, im selben Dialog beim NAT Netzwerk unter Port Weiterleitung folgende Regeln anlegen:

| Name | Host Port | Gast IP | Gast Port |
|---|---|---|---|
| SSH zur Management VM | 2250 | Adresse von ak-mgmt | 22 |
| Artifact Keeper über die VIP | 30090 | 10.0.10.250 | 80 |
| Artifactory | 8092 | Adresse von ak-ha3 | 8082 |

## Schritt 2: Rocky Linux installieren

Auf allen vier VMs Rocky Linux 10 Minimal aus der ISO installieren. Netzwerk auf DHCP lassen, ein Administratorkonto anlegen (im Beispiel `rocky`, Mitglied von wheel). Sonst ist nichts zu tun. Nach der Installation zeigt `ip -br a` auf jeder VM die vergebene Adresse.

## Schritt 3: Management VM einrichten

```bash
sudo dnf -y install ansible-core git
git clone <repository> && cd <repository>/ansible
ansible-galaxy collection install -r requirements.yml -p collections
```

Die Adressen der drei Knoten in `inventories/natnetwork/hosts.yml` eintragen. Im Test vergab das DHCP des NAT Netzwerks 10.0.10.3 an die Management VM und 10.0.10.4 bis .6 an die Knoten, in der Reihenfolge des ersten Starts.

## Schritt 4: Knoten übernehmen

```bash
tools/copy-ssh-keys.sh inventories/natnetwork/hosts.yml              # fragt je Knoten das Installationspasswort
ansible-playbook -i inventories/natnetwork/hosts.yml playbooks/bootstrap.yml -K
```

`copy-ssh-keys.sh` erzeugt auf der Management VM einen SSH Schlüssel und verteilt ihn mit `ssh-copy-id`. Das Playbook `bootstrap.yml` fragt einmal das sudo Passwort ab und erledigt dann drei Dinge:

* Es erlaubt dem Administratorkonto sudo ohne Passwort, damit alle weiteren Läufe ohne Eingabe laufen. Die Datei wird vor dem Schreiben mit `visudo` geprüft.
* Es trägt die per DHCP erhaltene Adresse fest in NetworkManager ein. Cluster, VIP und Inventory beziehen sich auf feste Adressen, eine neue Lease würde den Cluster zerlegen. Die Adresse ändert sich dabei nicht, die laufende Verbindung bleibt bestehen.
* Es setzt den Hostnamen auf den Namen aus dem Inventory.

## Schritt 5: Cluster und Migrationsquelle aufbauen

```bash
tools/generate-vault.py inventories/natnetwork/group_vars/all/vault.yml
export ANSIBLE_VAULT_PASSWORD_FILE=~/.ansible/ak-vault-pass
ansible-playbook -i inventories/natnetwork/hosts.yml playbooks/site.yml          # Hochverfügbarkeitssystem
ansible-playbook -i inventories/natnetwork/hosts.yml playbooks/artifactory.yml   # JFrog Container Registry auf ak-ha3
```

`site.yml` ist dasselbe Playbook wie in [08](08-ansible.md). Für das NAT Netzwerk unterscheidet sich nur das Inventory: Clusternetz 10.0.10.0/24, VIP 10.0.10.250 und die Freigabe des Backends für Artifactory auf ak-ha3.

## Schritt 6: Migration

Das Inventory nutzt JFrog Container Registry als Quelle. Die Annahme der Lizenzvereinbarung ist dort mit `artifactory_oss_accept_eula: true` eingetragen und gilt für dieses Labor. Wer das nicht möchte, setzt den Wert auf `false` und nimmt sie in der Oberfläche an.

```bash
ansible-playbook -i inventories/natnetwork/hosts.yml playbooks/jcr_seed.yml   # nur im Labor, lädt Images und Dateien aus dem Internet
ansible-playbook -i inventories/natnetwork/hosts.yml playbooks/migrate.yml --tags artifacts,verify,verify_images,security,verify_access
```

Die Playbooks laufen auf ak-ha3 (Gruppe `migration_runner`). Von dort sind die VIP und die Quelle erreichbar. Ergebnisse und Einzelheiten stehen in [03](03-migration.md) und [12](12-rechte-und-identitaeten.md).

## Schritt 7: Identitätsanbieter (optional)

Keycloak läuft bewusst außerhalb des Clusters auf der Management VM, wie ein Identitätsanbieter in Produktion. Die Management VM braucht dafür 2 GB RAM. Die Adresse von ak-mgmt muss im Inventory stimmen, sie wird zum Issuer.

```bash
ansible-playbook -i inventories/natnetwork/hosts.yml playbooks/keycloak.yml
ansible-playbook -i inventories/natnetwork/hosts.yml playbooks/artifact_keeper.yml -e ak_oidc_enabled=true
```

Vor dem Anlegen von Benutzern ist die Reihenfolge aus [12](12-rechte-und-identitaeten.md) zu beachten. In einem bestehenden Vault fehlen die Keycloak Werte, die mit `ansible-vault edit` zu ergänzen sind, siehe `tools/generate-vault.py`.

## Testergebnis

Getestet am 4. November 2026 mit VirtualBox 7.2 auf vier frisch installierten VMs. Die drei Knoten hatten eine schlichte Minimalinstallation mit DHCP, ohne SSH Schlüssel und mit sudo nur gegen Passwort, also genau den Stand nach einer Installation von Hand. Die Management VM hatte nur `ansible-core`.

| Schritt | Ergebnis |
|---|---|
| SSH Schlüssel verteilen mit `copy-ssh-keys.sh` | alle drei Knoten erreichbar |
| `bootstrap.yml` mit `-K` | sudo vorher nur mit Passwort, danach ohne. DHCP Adressen .4 bis .6 fest eingetragen, Hostnamen gesetzt. |
| `site.yml` | erfolgreich. Patroni mit Leader und Replica, OpenSearch green mit drei Knoten, Upload und Download über die VIP |
| VIP im NAT Netzwerk | Die Prüfung auf belegte Adressen lief sauber durch, VRRP funktioniert, die VIP antwortet von allen VMs aus |
| Zugriff vom Host | über die Portweiterleitung des NAT Netzwerks auf die VIP erreichbar (`localhost:30090`, `X-Served-By: ak-ha1`) |
| `artifactory.yml` auf ak-ha3 | Artifactory gesund, Standardpasswort von `admin` per Playbook ersetzt |
| Testdaten OSS und `migrate.yml` | 59 Einträge mit 26 MB übertragen, 58 von 58 Dateien über die VIP bitgenau, drei Benutzer, zwei Gruppen und die übertragbaren Regeln übernommen |
| `jcr_seed.yml` und `migrate.yml` mit JCR | 24 von 24 Images und 6 von 6 Dateien identisch, 7 Gruppen und 22 Benutzer exakt übernommen, Zugriffsmatrix 13 von 14 gleich |
| Keycloak mit OIDC | Anmeldung, Gruppen und Administratorvergabe funktionieren in der richtigen Reihenfolge, siehe [12](12-rechte-und-identitaeten.md) |
| ansible lint im Profil production und yamllint | keine Befunde in 158 Dateien |

Das Ausfallverhalten wurde in diesem Labor nicht noch einmal gemessen. Die Rollen sind dieselben wie in [08](08-ansible.md) und [09](09-offline.md), wo ein harter Ausfall eines Knotens etwa 44 Sekunden Unterbrechung und ein Rolling Update keine Fehler ergab.

Ein Fehler zeigte sich nur hier: Das Playbook für die Testdaten erzeugt die Dateien auf dem Knoten mit Artifactory, `uri` suchte sie für den Upload aber auf dem Steuerknoten. Auf dem Einzelknoten fiel das nicht auf, weil beides derselbe Rechner ist. Behoben mit `remote_src: true`.
