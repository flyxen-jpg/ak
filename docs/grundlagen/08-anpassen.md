# 8 Was sich anpassen lässt

[Zurück: Ansible](07-ansible.md) | [Übersicht Grundlagen](README.md)

Änderungen gehören ins Inventory der eigenen Umgebung und nicht in die Rollen. So bleiben Rollen für alle Umgebungen gleich. Am einfachsten kopiert man `inventories/natnetwork` und passt die Kopie an.

## Häufige Änderungen

| Vorhaben | Wo | Variable oder Datei |
|---|---|---|
| Andere Adressen oder mehr Knoten | Inventory | `hosts.yml`, Feld `ansible_host` |
| Andere VIP | Inventory | `ak_vip`. Die Adresse muss frei sein und darf nicht im DHCP Bereich liegen. |
| Anderes Netz | Inventory | `ak_cluster_network` |
| Adresse für die Benutzer | Inventory | `ak_external_url`, in Produktion ein DNS Name mit HTTPS |
| Andere Version von Artifact Keeper | Rolle, Vorgabe überschreiben | siehe `roles/artifact_keeper/defaults/main.yml`, danach `artifact_keeper.yml` |
| Eigene Images für den Test | Vorgabe überschreiben | `artifactory_migration_images` |
| Eigene Gruppen für den Test | Vorgabe überschreiben | `artifactory_migration_jcr_groups`, `artifactory_migration_jcr_permissions` |
| Eigene Fälle für die Zugriffsmatrix | Vorgabe überschreiben | `artifactory_migration_access_tests` |
| Welche Repositories umziehen | Inventory | `artifactory_migration_repos` |
| Rechte mit Pfadmustern | Inventory | `artifactory_migration_security_mode: strict` oder `broad` |
| Mit Identitätsanbieter | Inventory | `artifactory_migration_identity_mode: idp`, `ak_oidc_enabled`, `ak_oidc_env` |
| Quelle: OSS oder JCR | Inventory | `artifactory_oss_edition` |
| Weitere Umgebungsvariablen für Artifact Keeper | Inventory | `artifact_keeper_extra_env` |

## Auf dem Weg zur Produktion

Das Labor ist bewusst schlicht gehalten. Vor einem produktiven Einsatz stehen diese Änderungen an:

| Punkt | Im Labor | In Produktion |
|---|---|---|
| Verschlüsselung für Clients | HTTP | HTTPS mit Zertifikat an HAProxy |
| Name | Port am Host | DNS Name, von allen Clients auflösbar |
| Knoten | zwei Anwendungsknoten und ein kleiner dritter | drei gleichwertige Knoten oder ein Witness |
| Größe | 2,5 bis 3,5 GB RAM | nach Last bemessen, deutlich mehr |
| Speicher | Garage auf den Knoten | vorhandenes S3, wenn möglich |
| Datenbank | Patroni auf den Knoten | verwaltete Datenbank, wenn vorhanden |
| Keycloak | Testinstanz ohne dauerhafte Daten | der vorhandene Identitätsanbieter |
| Netz | ein gemeinsames Netz | getrennte Segmente, siehe [Netzwerk](02-netzwerk.md) |
| Überwachung | von Hand | `/readyz`, HAProxy, Patroni und OpenSearch überwachen |
| Backup | beschrieben, nicht als Probe getestet | regelmäßig, mit erprobter Wiederherstellung |

## Wenn etwas schiefgeht

| Beobachtung | Mögliche Ursache | Prüfung |
|---|---|---|
| Ansible meldet `UNREACHABLE` | Adresse falsch, Schlüssel fehlt | `ansible all -m ansible.builtin.ping` |
| `Host key verification failed` oder `REMOTE HOST IDENTIFICATION HAS CHANGED` | Unter derselben Adresse antwortet ein anderer Rechner. | Erst klären, warum, dann den Eintrag entfernen. |
| VIP antwortet nicht | keepalived oder HAProxy gestoppt, Adresse doppelt | `ip -br a` auf den Knoten, Log von keepalived |
| `docker login` scheitert, die VIP antwortet aber | `AK_EXTERNAL_URL` vom Client aus nicht erreichbar | `curl -i http://<vip>/v2/`, Feld `realm` |
| Anmeldung über Keycloak endet mit 409 | lokales Konto gleichen Namens | [Kapitel 12](../12-rechte-und-identitaeten.md) |
| Benutzer aus Keycloak hat keine Rechte | gleichnamige lokale Gruppe | Spalte `external_source` der Gruppe prüfen |
| Pull meldet `repository not found` | meist fehlendes Leserecht, Artifact Keeper verbirgt die Existenz | Regeln des Benutzers prüfen |
| Oberfläche von JCR hängt | wenig Speicher, Fehler im Frontend Dienst | `free -m`, Log `entitlement fetch failed` |
| Altes Passwort von JCR funktioniert noch | Zwischenspeicher der REST API | einige Minuten warten, erneut prüfen |

Weitere Hilfe bietet das [Betriebshandbuch](../07-betrieb.md).
