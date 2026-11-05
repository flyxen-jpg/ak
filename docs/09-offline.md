# 09 Installation ohne Internetanbindung

[Zurück: Ansible](08-ansible.md) | [Übersicht](README.md) | [Weiter: Einzelknoten](10-einzelknoten.md)

Der komplette Cluster lässt sich in einem Netz ohne jede Verbindung nach außen installieren, in VirtualBox ebenso wie auf jeder anderen Infrastruktur. Alles, was sonst aus dem Internet käme, wird vorher auf einem angebundenen Rechner in ein Offline Bundle gepackt.

## Vorbereitung

### Außerhalb des isolierten Netzes auf einem Rechner mit Internet

| Schritt | Begründung |
|---|---|
| Einen Rechner mit Rocky Linux oder RHEL 10.x auf x86_64 bereitstellen, eine VM genügt. Er braucht `ansible-core`, sudo und dieselbe Minor Release wie die Zielknoten. | RPMs und die Auflösung der Abhängigkeiten müssen zur Release der Zielknoten passen. |
| Das Projekt auschecken: `git clone ... && cd ansible` | Das Bundle wird aus den Defaults der Rollen erzeugt. |
| Bei Bedarf Versionen in `roles/*/defaults/main.yml` oder im Inventory anpassen. | Das Bundle enthält genau die dort festgelegten Versionen. |
| `ansible-playbook playbooks/bundle.yml -e bundle_dir=/srv/ak-bundle` ausführen. | Das Playbook lädt Pakete, Images und Collections. |
| Das Verzeichnis des Bundles übertragen, etwa per USB, Datendiode oder Transferserver. | etwa 6,2 GB |

Das Bundle in `/srv/ak-bundle` enthält:

| Datei | Inhalt | Herkunft |
|---|---|---|
| `rpms.tar` | lokales dnf Repository mit Metadaten. Es umfasst alle Pakete der Rollen mit ihrer vollständigen Abhängigkeitskette sowie `ansible-core` für den Steuerknoten, im Labor 454 RPMs mit 650 MB. | Rocky BaseOS und AppStream, EPEL, PGDG |
| `rpm-gpg/` | Signaturschlüssel von Rocky 10, EPEL 10 und PGDG, ohne den Testing Schlüssel von Rocky | `/etc/pki/rpm-gpg` des Bundle Rechners |
| `images/*.tar` | etcd, Garage, OpenSearch sowie Backend und Web von Artifact Keeper, zusammen 5,4 GB | quay.io, docker.io, ghcr.io |
| `collections/` | `ansible.posix` 2.2.2 | Ansible Galaxy |
| `ansible-project.tar.gz` | das Ansible Projekt ohne Vault | Repository |
| `MANIFEST.yml`, `BUNDLE_ID` | Liste der Pakete und Images, Kennung aus Datum und Hash | wird beim Bau erzeugt |
| `SHA256SUMS` | Prüfsummen aller Dateien | wird beim Bau erzeugt |

Die Abhängigkeiten werden über eine echte dnf Transaktion in ein leeres Installroot aufgelöst, das `@core` und alle Pakete enthält (`dnf install --downloadonly --installroot ...`). Der naheliegende Weg über `dnf download --resolve --alldeps` reicht nicht, weil er bedingte Abhängigkeiten wie `(passt-selinux if selinux-policy-targeted)` ignoriert. Im Test ließ sich Podman deshalb zunächst nicht offline installieren. Beim Download werden die Pakete nicht geprüft, denn das leere Installroot kennt keine Schlüssel. Jeder Zielknoten prüft sie aber bei der Installation gegen die Schlüssel der Hersteller (`gpgcheck=1`).

Die Images liegen als Archiv im Bundle, damit im isolierten Netz keine zusätzliche Software wie eine eigene Registry nötig ist. Ansible kopiert jedes Archiv nur auf die Knoten, die es brauchen, lädt es mit `podman load` und löscht es danach. Gibt es bereits eine interne Registry, etwa Harbor, Quay oder ein bestehendes Artifact Keeper, können die Image Namen in den Defaults der Rollen auch dorthin zeigen.

### Im isolierten Netz

| Voraussetzung | Hinweis |
|---|---|
| Steuerknoten mit Rocky Linux oder RHEL 10 und sudo | `ansible-core` kommt aus dem Bundle, falls es fehlt. |
| Zielknoten mit Minimalinstallation, SSH Schlüssel, sudo ohne Passwort und statischer IP | keine weiteren Pakete nötig |
| freie IP für die VIP im selben Layer 2 Netz | Die Vorabprüfung der Rolle `keepalived` bricht bei einem Konflikt ab. |
| interne Zeitquelle über `base_chrony_servers` | Ohne Zeitquelle laufen die Uhren auseinander, was etcd, Patroni und TLS stört. |
| internes DNS ist optional | Ohne DNS pflegt die Rolle `base` die Datei `/etc/hosts`. |
| etwa 10 GB frei auf dem Steuerknoten und etwa 15 GB je App Knoten | Platz für das Bundle und die entpackten Images |

## Ablauf im isolierten Netz

```bash
# Steuerknoten: Bundle prüfen, Projekt auspacken, ansible-core und Collection installieren
sudo mkdir -p /srv/ak-bundle && sudo chown $USER /srv/ak-bundle   # Bundle hierhin kopieren
tar -xzf /srv/ak-bundle/ansible-project.tar.gz -C ~ && cd ~/ansible
tools/install-control-node.sh /srv/ak-bundle      # prüft SHA256SUMS, installiert ansible-core (signiert) und ansible.posix

# Inventory anpassen: in VirtualBox virtualbox-offline, sonst eine Kopie von airgapped
tools/generate-vault.py inventories/virtualbox-offline/group_vars/all/vault.yml
export ANSIBLE_VAULT_PASSWORD_FILE=~/.ansible/ak-vault-pass
ansible-playbook -i inventories/virtualbox-offline/hosts.yml playbooks/site.yml
```

Ohne Internet verhält sich das Projekt in diesen Punkten anders. Gesteuert wird das über `ak_offline: true`.

| Bereich | mit Internet | ohne Internet |
|---|---|---|
| Quellen für RPMs | Spiegelserver von Rocky, EPEL und PGDG, die Repositories werden eingerichtet | Die Rolle `offline_repo` richtet ein Repository über `file://` aus dem Bundle ein, schaltet alle anderen Repositories ab und stoppt `dnf-makecache.timer`. |
| Images | `podman pull` | Archiv kopieren, mit `podman load` laden und danach löschen |
| Collections | `ansible-galaxy ... -r requirements.yml` | `install-control-node.sh` aus dem Bundle |
| Prüfung der Signaturen | ja | ja, mit den Schlüsseln aus dem Bundle und `gpgcheck=1` |

Die Rollen sind in beiden Fällen dieselben. Jede Quadlet Unit startet mit `Pull=never`. Fehlt ein Image, gibt es daher sofort einen klaren Fehler und keinen Hänger an einer unerreichbaren Registry.

## VirtualBox ohne Internet nachstellen

Der Aufbau entspricht dem bestehenden Labor, nur ohne NAT.

```powershell
# VMs anlegen (Kickstart von der Minimal-ISO, NAT dient nur dem ersten SSH-Zugang)
powershell -File vm\create-node.ps1 -Name ans-ctl   -Ip 192.168.56.20 -SshPort 2230 -MemoryMB 1280 -NoHosts
powershell -File vm\create-node.ps1 -Name ans-node1 -Ip 192.168.56.21 -SshPort 2231 -MemoryMB 3072 -NoHosts
# ebenso ans-node2 (.22) und ans-node3 (.23, 2048 MB)
# Internet trennen, indem das NAT-Kabel gezogen wird. Danach bleibt nur das Host-Only-Netz 192.168.56.0/24.
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" controlvm ans-node1 setlinkstate1 off
```

Danach ist der Steuerknoten nur noch über `ssh rocky@192.168.56.20` erreichbar, zum Beispiel mit `vm\ansible-run.ps1 -Target 192.168.56.20 -Port 22 ...`. Ob tatsächlich keine Verbindung nach außen besteht, zeigt `curl -m5 https://quay.io` auf jedem Knoten. Der Aufruf muss fehlschlagen.

## Ohne VirtualBox und ohne Internet

Der Ablauf ist derselbe, nur mit einer Kopie von `inventories/airgapped/`. Von der Plattform hängen lediglich diese Punkte ab:

* VRRP für die VIP: bei VMware „MAC address changes“ und „Forged transmits“, bei Hyper V „MAC address spoofing“
* Netzwerkkarte: wird aus `ak_cluster_ip` erkannt, eine Konfiguration ist nicht nötig
* Zeit: `base_chrony_servers` auf interne NTP Server setzen
* Speicher: eigene Dateisysteme für `/home/ak/.local/share/containers` mit den Images und den Daten von Garage und OpenSearch sowie für `/var/lib/pgsql`

Dieses Szenario wurde nicht auf echter Hardware getestet. Die Rollen enthalten aber nichts, was nur in VirtualBox funktioniert.

## Aktualisierung im isolierten Netz

1. Außerhalb die Versionen anheben und `bundle.yml` erneut ausführen. Das Bundle erhält eine neue `BUNDLE_ID`.
2. Das Bundle übertragen und mit `sha256sum -c SHA256SUMS` prüfen.
3. `ansible-playbook ... playbooks/site.yml` ausführen. Die Rolle `offline_repo` legt das neue Repository unter der neuen `BUNDLE_ID` an und entfernt das alte. Images werden nur geladen, wenn sie fehlen, und Artifact Keeper wird Knoten für Knoten aktualisiert.

## Testergebnis

Am 4. November 2026 wurde das Bundle auf `ans-ctl` mit Internet gebaut. Danach wurden alle vier VMs vom NAT getrennt. Sie hatten damit keine Default Route und keine Namensauflösung mehr, `curl https://quay.io` schlug fehl. Die drei Clusterknoten wurden frisch aus dem Kickstart installiert, auf dem Steuerknoten wurde `ansible-core` deinstalliert und das Projekt gelöscht. Alles Weitere kam ausschließlich aus dem Bundle.

| Schritt | Ergebnis |
|---|---|
| `install-control-node.sh` mit Prüfung der Prüfsummen, `ansible-core` 2.16.16 aus signierten RPMs und `ansible.posix` 2.2.2 | erfolgreich |
| `site.yml` auf frischen Knoten | erfolgreich in 9 Minuten 42 Sekunden mit ok=378 und failed=0. VIP, Patroni mit Leader und Replica, OpenSearch green, Upload und Download über die VIP. |
| zweiter Lauf | keine Änderungen außer dem bewusst neuen Upload des Funktionstests |
| Wechsel des Bundles mit neuer `BUNDLE_ID` | Das neue Repository ist aktiv, das alte Verzeichnis wurde auf allen Knoten entfernt. |
| Rolling Update von Artifact Keeper mit `artifact_keeper.yml` unter Last | keine Fehler bei 106 Anfragen |
| Knoten hart aus und wieder an | etwa 44 Sekunden Unterbrechung, nach dem Booten automatische Rückkehr als Replica |

Zwei Fehler zeigten sich nur ohne Internet und sind behoben. Im Bundle fehlten bedingte Abhängigkeiten wie `passt-selinux`, und die Repository URLs von PGDG enthalten `$releasever_minor`. Die Einzelheiten stehen in [08](08-ansible.md). Die Rohdaten liegen unter `lab/results/ansible-*`.

Im Labor war `ans-ctl` zugleich Bundle Rechner und Steuerknoten. Für den Bau des Bundles wurde nur dessen NAT kurz wieder verbunden, die Clusterknoten blieben die ganze Zeit offline. In der Praxis sind das zwei getrennte Rechner, einer außerhalb und einer innerhalb des isolierten Netzes.
