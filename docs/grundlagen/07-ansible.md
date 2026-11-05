# 7 Ansible und die Skripte dieses Projekts

[Zurück: Benutzer und Rechte](06-identitaeten.md) | [Übersicht Grundlagen](README.md) | [Weiter: Anpassen](08-anpassen.md)

## Was Ansible tut

**Ansible** richtet Rechner nach einer Beschreibung ein. Statt Befehle von Hand einzugeben, beschreibt man den gewünschten Zustand: „Das Paket ist installiert, die Datei hat diesen Inhalt.“ Ansible meldet sich per SSH an und ändert nur, was abweicht. Auf den Zielrechnern ist dafür nichts außer Python nötig, was Rocky Linux schon mitbringt.

**Idempotent** heißt: Ein zweiter Lauf ändert nichts mehr, wenn alles stimmt. Das macht Playbooks gefahrlos wiederholbar und ist die Grundlage dafür, dass ein Fehler einfach behoben und der Lauf neu gestartet werden kann.

## Die Bausteine

| Baustein | Was es ist | Beispiel im Projekt |
|---|---|---|
| Inventory | Liste der Rechner und ihrer Gruppen | `inventories/natnetwork/hosts.yml` |
| Variable | einstellbarer Wert | `ak_vip: 10.0.10.250` |
| Task | ein einzelner Schritt mit einem Modul | Paket installieren |
| Modul | fertiger Baustein von Ansible | `ansible.builtin.dnf` |
| Handler | Task, die nur nach einer Änderung läuft | Dienst neu starten, wenn sich seine Konfiguration geändert hat |
| Template | Datei mit Platzhaltern (Jinja2) | `keycloak.env.j2` |
| Rolle | Sammlung für eine Aufgabe aus Tasks, Vorgaben, Templates | `roles/keycloak` |
| Playbook | sagt, welche Rollen auf welchen Rechnern laufen | `playbooks/keycloak.yml` |
| Vault | verschlüsselte Datei für Geheimnisse | `vault.yml` |

## Wie es zusammenspielt

Ein kurzes, echtes Beispiel. Das Playbook `playbooks/keycloak.yml`:

```yaml
- name: Install Keycloak
  hosts: identity_provider
  gather_facts: true
  roles:
    - role: keycloak
      tags: [keycloak]
```

Das bedeutet: Führe auf allen Rechnern der Gruppe `identity_provider` die Rolle `keycloak` aus. Welche Rechner das sind, steht im Inventory:

```yaml
identity_provider:
  hosts:
    ak-mgmt:
      ansible_host: 10.0.10.3
      ansible_connection: local
```

Die Rolle folgt immer demselben Aufbau:

```text
roles/keycloak/
├── defaults/main.yml    Vorgaben, die jeder überschreiben darf
├── meta/main.yml        Abhängigkeiten, hier die Rolle podman
├── handlers/main.yml    Neustart nach Änderungen
├── tasks/main.yml       die Schritte der Reihe nach
└── templates/           Dateien mit Platzhaltern
```

### Reihenfolge der Variablen

Derselbe Wert kann an mehreren Stellen stehen. Von schwach nach stark:

| Stelle | Zweck |
|---|---|
| `roles/<rolle>/defaults/main.yml` | Vorgabe der Rolle |
| `inventories/<umgebung>/group_vars/all/main.yml` | Wert für diese Umgebung |
| `roles/<rolle>/vars/main.yml` | feste Daten der Rolle, nicht zum Überschreiben gedacht |
| `-e name=wert` auf der Kommandozeile | stärkste Stufe, für einen einzelnen Lauf |

### Geheimnisse

Passwörter liegen verschlüsselt in `vault.yml`. Die Datei `secrets.yml` daneben ist unverschlüsselt und bildet nur Namen aufeinander ab:

```yaml
keycloak_admin_password: "{{ vault_keycloak_admin_password }}"
```

So lässt sich im Klartext nachvollziehen, welche Geheimnisse es gibt, ohne ihre Werte zu sehen. `tools/generate-vault.py` erzeugt die Datei mit Zufallswerten. Das Passwort für den Vault liegt in `~/.ansible/ak-vault-pass` und gehört zusätzlich in einen Passwortmanager. `no_log: true` an einer Task verhindert, dass Geheimnisse in der Ausgabe landen.

### Tags

Tags wählen Teile eines Playbooks aus. `--tags verify` führt nur die Prüfung aus. Das besondere Tag `never` sorgt dafür, dass ein Teil nur läuft, wenn er ausdrücklich genannt wird.

## Playbooks im Projekt

| Playbook | Aufgabe | Läuft auf |
|---|---|---|
| `bootstrap.yml` | Einmalig: sudo ohne Passwort, Adresse fest eintragen, Hostname | Knoten |
| `site.yml` | ruft die sechs folgenden der Reihe nach auf | alle |
| `prepare.yml` | Betriebssystem vorbereiten, offline das lokale Repository | Cluster |
| `infrastructure.yml` | etcd, Garage, OpenSearch | Cluster |
| `database.yml` | PostgreSQL und Patroni | `ak_app` |
| `loadbalancer.yml` | HAProxy, keepalived | `ak_app` |
| `artifact_keeper.yml` | Anwendung, ein Knoten nach dem anderen | `ak_app` |
| `verify.yml` | Test über die VIP von Anfang bis Ende | Cluster |
| `artifactory.yml` | Quelle der Migration installieren | `artifactory` |
| `jcr_seed.yml` | Testdaten für JCR: Images, Charts, Gruppen | `migration_runner` |
| `artifactory_seed.yml` | Testdaten für OSS | `migration_runner` |
| `migrate.yml` | Migration und Prüfungen, gesteuert über Tags | `migration_runner` |
| `keycloak.yml` | Identitätsanbieter für den Test | `identity_provider` |
| `standalone.yml` | alles auf einem einzigen Rechner | `standalone` |
| `bundle.yml` | Paket für die Installation ohne Internet | Rechner mit Internet |

Die Reihenfolge in `site.yml` folgt den Abhängigkeiten: Erst muss etcd laufen, dann kann Patroni starten. Erst steht die Datenbank, dann startet die Anwendung.

## Rollen im Projekt

| Rolle | Was sie tut | Wichtigste Gedanken |
|---|---|---|
| `offline_repo` | richtet ein lokales Paketlager aus dem Bundle ein | nur ohne Internet |
| `base` | Pakete, Zeit, `/etc/hosts`, Firewall | SSH wird freigegeben, bevor die Zone greift |
| `podman` | Podman, Konto `ak`, Linger, Bereitstellung von Images | Grundlage aller Container Rollen, per `meta` als Abhängigkeit |
| `etcd` | drei Mitglieder | zuerst, weil Patroni es braucht |
| `garage` | S3 Knoten, Layout, Bucket, Schlüssel | Schlüssel aus dem Vault, damit alle Knoten ihn kennen |
| `opensearch` | drei Knoten, Index Template | behebt die fehlenden Replikas |
| `patroni` | PostgreSQL und Patroni | erster Knoten initialisiert, zweiter klont |
| `haproxy` | gleiche Konfiguration auf beiden Knoten | wird vor dem Schreiben geprüft |
| `keepalived` | VIP | prüft, ob die Adresse frei ist |
| `artifact_keeper` | Backend und Web | Handler: Drain, Neustart, warten, Freigabe |
| `artifactory_oss` | OSS oder JCR, je nach `artifactory_oss_edition` | ersetzt das Standardpasswort sofort |
| `artifactory_migration` | Testdaten, Migration, Prüfung, Rechte | `tasks_from` wählt den Teil |
| `keycloak` | Testinstanz mit Realm aus einer Vorlage | Benutzer und Gruppen sind im Template definiert |
| `bootstrap` | erster Zugriff auf frische Rechner | braucht einmalig `-K` für das sudo Passwort |
| `standalone_host`, `ak_standalone` | Einzelknoten | Prüfungen vorab und eine einfachere Anwendungsrolle |

## Beispiel: Was bei einem Update passiert

Ändert sich die Konfiguration von Artifact Keeper, passiert in der Rolle `artifact_keeper` Folgendes:

1. Das Template erzeugt `backend.env` neu. Weicht die Datei ab, meldet die Task `changed` und benachrichtigt den Handler.
2. Der Handler nimmt den Knoten in HAProxy per Drain aus der Verteilung.
3. Der Dienst startet neu, und Ansible wartet, bis `/readyz` bereit meldet.
4. Der Knoten kommt zurück in die Verteilung.
5. `serial: 1` im Playbook sorgt dafür, dass erst danach der nächste Knoten an der Reihe ist.

So entsteht ein Rolling Update ohne Unterbrechung, auch im Test mit 0 Fehlern.

## Ausführen und prüfen

```bash
ansible-playbook -i inventories/natnetwork/hosts.yml playbooks/site.yml --check   # zeigt, was sich ändern würde, soweit das geht
ansible-playbook -i inventories/natnetwork/hosts.yml playbooks/site.yml --tags etcd
ansible -i inventories/natnetwork/hosts.yml ak_cluster -m ansible.builtin.ping
ansible-lint --profile production
yamllint .
```

Die Regeln für den Stil folgen den Empfehlungen von [ATIX](https://atix.de/en/blog/ansible-best-practices/): vollständige Modulnamen wie `ansible.builtin.copy`, ein Name an jeder Task, `become` je Task, Variablen mit dem Namen der Rolle als Vorsilbe. Die Kommentare im Code sind auf Englisch und erklären knapp, warum etwas so gelöst ist. Die vollständige Liste steht in [Kapitel 08](../08-ansible.md).
