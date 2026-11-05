# 12 Benutzer, Gruppen, Rechte und Identitätsanbieter

[Zurück: NAT Netzwerk](11-nat-netzwerk.md) | [Übersicht](README.md)

Dieses Kapitel belegt, warum die eingebaute Migration von Artifact Keeper Benutzer, Gruppen und Rechte nicht überträgt, worin sich die Modelle beider Produkte unterscheiden, was sich trotzdem übernehmen lässt und wie ein Identitätsanbieter eingebunden wird. Jede Aussage trägt eine Fundstelle oder einen Test und lässt sich mit den Befehlen im Abschnitt [Nachstellen](#nachstellen) wiederholen.

Der Quelltext bezieht sich auf Artifact Keeper `v1.11.11`, Commit `faec02d0`. Die Rohdaten des Testlaufs liegen unter [`lab/results/jcr-migration/`](../lab/results/jcr-migration/).

## Ergebnis

| Frage | Ergebnis | Beleg |
|---|---|---|
| Überträgt der Migrationsjob Benutzer, Gruppen und Rechte? | Nein, auch nicht mit gesetzten Optionen | Abschnitt [Warum die eingebaute Migration das nicht leistet](#warum-die-eingebaute-migration-das-nicht-leistet) |
| Lassen sich ganze Gruppen trotzdem kopieren? | Ja, mit `playbooks/migrate.yml`. 7 Gruppen und 22 Benutzer stimmten exakt überein. | Test [Gruppen](#gruppen-kopieren) |
| Verhalten sich die Rechte danach gleich? | In 13 von 14 Fällen ja. Der eine Unterschied ist ein Pfadmuster und strenger als zuvor. | Test [Zugriffsmatrix](#zugriffsmatrix) |
| Kann ein migrierter lokaler Benutzer sich danach über Keycloak anmelden? | Nein, die Anmeldung endet mit HTTP 409. | Test [Keycloak](#identitätsanbieter-am-beispiel-keycloak) |
| Wird eine Keycloak Gruppe mit einer gleichnamigen migrierten Gruppe verbunden? | Nein, die Mitgliedschaft wird abgelehnt und der Benutzer steht ohne Rechte da. | Test [Keycloak](#identitätsanbieter-am-beispiel-keycloak) |
| Gibt es einen sauberen Weg mit Identitätsanbieter? | Ja: Nur Rechte migrieren, Benutzer und Gruppen entstehen bei der Anmeldung. | Abschnitt [Empfohlener Ablauf](#empfohlener-ablauf-mit-identitätsanbieter) |

## Warum die eingebaute Migration das nicht leistet

Die Ursache liegt in Artifact Keeper und nicht an einer fehlenden Berechtigung auf der Quelle. Die Funktion fehlt an fünf voneinander unabhängigen Stellen.

| Nr. | Befund | Fundstelle | Prüfung |
|---|---|---|---|
| 1 | `migrate_users`, `migrate_groups` und `migrate_permissions` werden nirgends aufgerufen. Im gesamten Quelltext stehen nur ihre Definitionen. | `backend/src/services/migration_worker.rs:2970`, `:3095`, `:3191` | `source-check.sh`, Punkt 1 |
| 2 | Die Optionen `include_users`, `include_groups` und `include_permissions` werden vom Server nur gespeichert. Ausgewertet werden sie allein im Kommandozeilenpfad. | `backend/src/models/migration.rs:129`, `backend/src/cli/migrate_runner.rs:270` | `source-check.sh`, Punkt 2 |
| 3 | Dieser Kommandozeilenpfad listet die Objekte nur auf und endet an Platzhaltern. | `backend/src/cli/migrate_runner.rs:287`, `:300`, `:325` (`TODO: Create user in Artifact Keeper`) | `source-check.sh`, Punkt 3 |
| 4 | Die Funktionen würden auch bei einem Aufruf scheitern. Sie schreiben in Spalten und eine Tabelle, die das Datenbankschema nicht kennt. | `migration_worker.rs:3076`, `:3174` und die Tabelle `repository_permissions`, die keine Migration anlegt | `database-check.sql`, Punkte 1 bis 4 |
| 5 | Selbst ohne diese Fehler bliebe das Ergebnis unvollständig. `migrate_groups` legt nur die Gruppe an, nie ihre Mitglieder. `map_permission` kennt `write` und `manage` nicht, die Namen der Artifactory API v2, und verwirft diese Rechte ohne Meldung. | `migration_worker.rs:3132`, `backend/src/services/migration_service.rs:437` | `source-check.sh`, Punkt 5 |

### Ausgabe der Datenbank im Labor

Die Anweisungen sind wörtlich aus dem Quelltext übernommen und laufen in einer Transaktion, die zurückgerollt wird.

```text
INSERT INTO users (username, email, role, status, metadata) ...
ERROR:  column "role" of relation "users" does not exist

INSERT INTO groups (name, description, metadata) ...
ERROR:  column "metadata" of relation "groups" does not exist

SELECT to_regclass('public.repository_permissions');
(leer, die Tabelle existiert nicht)
```

Alle drei Jobs des Labors haben die Optionen gesetzt und trotzdem nur Artefakte bearbeitet:

```text
                  id                  |  status   | users | groups | permissions | total_items
 e43db2a0-d4a3-44f4-a1aa-49a8eb7df218 | completed | true  | true   | true        |           0
 0905dc9c-014f-4399-8382-a2f3941f38ff | completed | true  | true   | true        |          59
 fdc8d65c-db2f-497d-ba7d-bb33848da1fa | completed | true  | true   | true        |         583

 item_type |  status   | count
 artifact  | completed |   372
```

Die Zahl 372 enthält nur Einträge, die übertragen wurden. Einträge vom Typ `user`, `group` oder `permission` gibt es nicht.

### Rolle der Quelle

Unabhängig davon sperrt die Quelle bei den kostenlosen Ausgaben die dafür vorgesehenen APIs. Der Client von Artifact Keeper ruft genau diese auf (`backend/src/services/artifactory_client.rs:933` bis `:949`).

| Aufruf auf JFrog Container Registry 7.161.26 | Antwort |
|---|---|
| `GET /artifactory/api/security/users` | 400, `This REST API is available only in Artifactory Pro` |
| `GET /artifactory/api/security/groups` | 400, gleiche Meldung |
| `GET /artifactory/api/v2/security/permissions` | 400, gleiche Meldung |
| `GET /access/api/v2/users` mit Basic Auth | 401, `Unsupported authentication method Basic` |

Eine lizenzierte Instanz liefert diese APIs laut JFrog aus. Das ändert am Ergebnis nichts, denn Artifact Keeper ruft den Code gar nicht auf. Eine lizenzierte Instanz stand für den Test nicht zur Verfügung.

## Was die Dokumentation sagt und was stimmt

| Aussage | Quelle | Befund | Beleg |
|---|---|---|---|
| Die Migrations API legt passende Rollen und Zuweisungen automatisch an | [Migration from Artifactory](https://artifactkeeper.com/docs/migration/from-artifactory/) | falsch | Befunde 1 bis 4 |
| Häkchen für Users, Groups und Permissions im Assistenten | Weboberfläche, Menü Migration | ohne Wirkung. Sie sind vorbelegt und werden gespeichert, bewirken aber nichts. | `database-check.sql`, Punkte 5 und 6 |
| Annotate wird Write, Delete wird Write | Migration from Artifactory | widerspricht dem Code. Dort wird Annotate zu Read und Delete zu Delete, und das Rechtemodell kennt ein eigenes Delete. | `migration_service.rs:437` |
| Docker Images werden von Hand mit `docker pull`, `tag` und `push` umgezogen | Migration from Artifactory | überholt, zugunsten des Produkts. Der Job überträgt Docker Repositories vollständig. | 24 von 24 Images identisch, siehe [03](03-migration.md) |
| `POST /migrations` mit `source_url`, `source_username`, `repositories` | [API Reference](https://artifactkeeper.com/docs/reference/api/) | veraltet. Die API verlangt `source_connection_id` und antwortet sonst mit 422. Die Migrationsseite beschreibt es richtig. | Test in [03](03-migration.md) |
| `POST /permissions` mit `repository_id`, `user_id`, `permissions` | API Reference, [Authentication & RBAC](https://artifactkeeper.com/docs/advanced/auth/) | veraltet. Es gilt `principal_type`, `principal_id`, `target_type`, `target_id`, `actions`. | `security_permissions.yml` läuft damit |
| Benutzer werden bei der Anmeldung angelegt oder aktualisiert | Authentication & RBAC | stimmt nur für Benutzer ohne lokales Konto. Ein gleichnamiges lokales Konto führt zu HTTP 409. Die Seite erwähnt das nicht. | Test Keycloak |
| `OIDC_MAP_GROUPS_TO_GROUPS` spiegelt Gruppen als lokale Gruppen | `.env.example`, Authentication & RBAC | unvollständig. Gleichnamige lokale Gruppen werden abgelehnt. Das steht nur im Quelltext. | `backend/src/api/handlers/sso.rs:1782` bis `:1804` |
| Mit SSO ist die lokale Anmeldung standardmäßig gesperrt, der Administrator behält einen Notzugang | `.env.example` | bestätigt. Der Administrator erhält HTTP 200, andere lokale Konten HTTP 401. Nicht erwähnt wird, dass die Registry deren Passwort weiter annimmt. | Test Keycloak, `backend/src/api/handlers/auth.rs:253` |

Die Seite Authentication & RBAC nennt für Rechte nur die Ebene des Repositorys. Das deckt sich mit dem Schema. Pfadmuster werden dort weder versprochen noch als fehlend genannt.

## Die beiden Modelle im Vergleich

Der Unterschied ist architektonisch. Eine Migration kann ihn nicht vollständig überbrücken.

| Merkmal | JFrog Artifactory | Artifact Keeper 1.11.11 | Folge |
|---|---|---|---|
| Grundobjekt | Permission Target: Sammlung von Ressourcen mit Benutzern, Gruppen und Aktionen | Regel: genau ein Principal, ein Ziel, eine Liste von Aktionen. `UNIQUE(principal_type, principal_id, target_type, target_id)`, `backend/migrations/018_groups_permissions.sql` | Ein Target wird zu mehreren Regeln. |
| Pfadmuster | Include und Exclude im Ant Stil je Repository | gibt es nicht. Spalten nur für Principal, Ziel, Aktionen und Bedingungen. | Regeln mit Muster lassen sich nicht abbilden. |
| Ressourcenarten | Repositories, Builds, Release Bundles, Destinations, Pipeline Sources | Repository, Projekt, Gruppe, Artefakt | Rechte auf Builds und Release Bundles haben keine Entsprechung. |
| Dynamische Auswahl | `Any Local`, `Any Remote` und damit auch künftige Repositories | Ziel ist immer eine konkrete ID, alternativ ein Projekt | Künftige Repositories brauchen eigene Regeln oder ein Projekt. |
| Aktionen | Read, Annotate, Deploy/Cache, Delete/Overwrite, Manage, Manage Xray Metadata | read, write, delete, admin | Annotate fällt weg und wird im Playbook zu read. |
| Kombination | Rechte addieren sich über alle Targets | Eine Regel je Principal und Ziel. Rechte aus Benutzer und Gruppen werden zusammen ausgewertet. | Das Playbook vereint die Aktionen mehrerer Targets. |
| Virtuelle Repositories | haben kein eigenes Target, es gelten die Mitglieder | eigene Objekte. Das Verhalten beim Zugriff über ein virtuelles Repository wurde nicht geprüft. | offen |
| Grundeinstellung ohne Regel | kein Zugriff. Die Gruppe `readers` kann per Auto Join Leserecht auf alles geben. | Sichtbarkeit `private`: kein Zugriff. `internal` erlaubt allen Angemeldeten das Lesen, `public` allen. | `readers` wird nicht übernommen, Leserechte müssen bewusst vergeben werden. |
| Rückmeldung ohne Leserecht | im Labor nicht gemessen | 404 oder `repository not found`, die Existenz bleibt verborgen | Fehlersuche im Client beachten. |
| Bedingungen an der Regel | keine in dieser Form | `allowed_cidrs` je Regel (`permission_service.rs:40`) | zusätzliche Möglichkeit |
| Gruppeneigenschaften | Auto Join, Admin Privileges, Rollen | Name, Beschreibung, `external_source` | Auto Join und Admin Privileges gehen verloren. |
| Passwörter | gehasht, nicht exportierbar | eigene Hashes | Einmalpasswort oder Anmeldung über den Identitätsanbieter |
| Zugriffstokens | Access Tokens und API Keys der Quelle | eigene API Tokens mit Scopes | Pipelines brauchen neue Zugangsdaten. |
| Identitätsabgleich | je nach Edition, siehe unten | über `external_id` und `auth_provider`, nicht über Name oder Mailadresse (`auth_service.rs:3595`) | Bestehende lokale Konten werden nicht verknüpft. |

Identitätsanbieter sind bei JFrog an die Edition gebunden. Laut [Feature Comparison Matrix](https://docs.jfrog.com/installation/docs/feature-comparison-matrix-for-self-mangaged-jpds) ist LDAP überall enthalten, LDAP Gruppen und SAML ab Pro X, OAuth erst ab Enterprise X. [JCR](https://docs.jfrog.com/artifactory/docs/container-registry-functionality) bietet nur LDAP. Artifact Keeper bringt OIDC, LDAP und SAML ohne Lizenz mit.

## Was übernommen wird und was nicht

| Objekt | Mit `playbooks/migrate.yml` | Bemerkung |
|---|---|---|
| Benutzer | ja, mit Mailadresse und Einmalpasswort | Passwörter lassen sich nicht übernehmen. Die Datei `/root/ak-migrated-users.txt` ist nur für root lesbar. |
| Gruppen samt Mitgliedern | ja, auch überlappende Mitgliedschaften | Wiederholte Läufe folgen der Quelle, entfernte Mitglieder werden auch im Ziel entfernt (`artifactory_migration_remove_stale_members`). |
| Regeln ohne Pfadmuster | ja | gegen echte Zugriffe geprüft |
| Regeln mit Pfadmuster | Modus `strict`: weggelassen und gemeldet. Modus `broad`: auf das ganze Repository ausgeweitet. | `broad` ist weniger streng als die Quelle und daher nur nach Prüfung sinnvoll. |
| Gruppe `readers` | nein | Leserecht muss ausdrücklich vergeben werden. |
| Auto Join, Admin Privileges | nein | Administratoren über `OIDC_ADMIN_GROUP` oder von Hand |
| Rechte auf Builds und Release Bundles | nein | keine Entsprechung |
| Access Tokens | nein | neu ausstellen |
| Konfiguration von LDAP, SAML oder OAuth | nein | in Artifact Keeper neu einrichten, ein Abgleich mit der Quelle findet nicht statt |

Die Quelle wird über die interne UI API gelesen (`/ui/api/v1/access/api/ui/...`), weil die REST APIs in JCR und OSS gesperrt sind. Auf einer lizenzierten Instanz ist das nicht getestet. Weil diese API intern ist, gehört ein Probelauf gegen die eigene Instanz zur Vorbereitung.

## Tests

Testumgebung: JFrog Container Registry 7.161.26 als Quelle auf `ak-ha3`, Hochverfügbarkeitssystem aus [11](11-nat-netzwerk.md) als Ziel, Keycloak 26.1.4 auf der Management VM.

### Gruppen kopieren

Die Testdaten bilden eine Organisation ab, in der Mitglieder mehreren Gruppen angehören. `ben`, `hanna` und `lena` sind zum Beispiel zugleich in einem Team und bei den `release-managers`.

| Gruppe | Mitglieder | fehlend im Ziel | zusätzlich im Ziel |
|---|---|---|---|
| `platform-admins` | 3 | 0 | 0 |
| `team-payments` | 5 | 0 | 0 |
| `team-checkout` | 5 | 0 | 0 |
| `team-data` | 4 | 0 | 0 |
| `release-managers` | 3 | 0 | 0 |
| `security-auditors` | 2 | 0 | 0 |
| `ci-robots` | 3 | 0 | 0 |

Der erste Lauf deckte einen Fehler im eigenen Playbook auf: In `release-managers` blieb `carol` aus einer früheren Migration zurück, weil Mitglieder nur hinzugefügt wurden. Wer in der Quelle aus einer Gruppe fliegt, hätte im Ziel seine Rechte behalten. Das Playbook entfernt solche Mitglieder jetzt, und eine eigene Prüfung vergleicht beide Seiten und bricht bei Abweichungen ab. Gruppen mit mehr als 200 Mitgliedern führen zu einem klaren Abbruch, weil die API je Seite höchstens 200 liefert und das Playbook kein Paging enthält.

### Zugriffsmatrix

Dieselben Vorgänge liefen mit echten Benutzern und dem Werkzeug `skopeo` gegen beide Systeme. Geprüft wurden echte Pulls und Pushes, nicht die Einträge in der Datenbank.

| Benutzer | Gruppen | Vorgang | JCR | Artifact Keeper |
|---|---|---|---|---|
| `dora` | `team-payments` | Pull `docker-base/alpine:3.21.3` | erlaubt | erlaubt |
| `dora` | `team-payments` | Pull `docker-prod/web/nginx:1.27.4-alpine` | verweigert | verweigert |
| `dora` | `team-payments` | Push nach `docker-base` | verweigert | verweigert |
| `hanna` | `team-payments`, `release-managers` | Pull `docker-prod/data/redis:7.4.2-alpine` | erlaubt | erlaubt |
| `hanna` | `team-payments`, `release-managers` | Push nach `docker-prod` | erlaubt | erlaubt |
| `ben` | `platform-admins`, `release-managers` | Push nach `docker-base` | erlaubt | erlaubt |
| `rita` | `security-auditors` | Pull `docker-prod/data/redis:7.4.2-alpine` | erlaubt | erlaubt |
| `rita` | `security-auditors` | Push nach `docker-prod` | verweigert | verweigert |
| `ci-payments` | `ci-robots`, plus eigene Regel | Push nach `docker-prod` | erlaubt | erlaubt |
| `ci-data` | `ci-robots` | Pull `docker-base/python:3.13.2-alpine` | erlaubt | erlaubt |
| `ci-data` | `ci-robots` | Push nach `docker-base` | verweigert | verweigert |
| `nina` | `team-data` | Pull `docker-prod/web/nginx:1.27.4-alpine` | verweigert | verweigert |
| `ivan` | `team-checkout` | Pull `docker-prod/web/nginx:1.27.4-alpine` | **erlaubt** | **verweigert** |
| `ivan` | `team-checkout` | Pull `docker-prod/data/redis:7.4.2-alpine` | verweigert | verweigert |

Der Unterschied bei `ivan` ist beabsichtigt und sicher: Das Target erlaubt `docker-prod` außer `data/**`. Artifact Keeper kennt dieses Muster nicht, im Modus `strict` entfällt die Regel. Abhilfe ist ein fachlicher Schnitt in Repositories, also ein eigenes Repository für `data`. Anonyme Pulls wurden auf beiden Repositories abgewiesen. Der Registryzugriff ist auch mit noch nicht geändertem Einmalpasswort möglich, obwohl das Konto `must_change_password` trägt.

### Identitätsanbieter am Beispiel Keycloak

Der Test läuft ohne Browser, führt aber den vollständigen Ablauf aus: Authorization Request, Anmeldeformular von Keycloak, Callback und Austausch des Codes (`tools/evidence/oidc-login.py`). Die Anmeldeseite im Browser wurde nicht geprüft, weil die Adresse von Keycloak im Labor vom Host aus nicht erreichbar ist.

**Reihenfolge 1: Erst Benutzer und Gruppen migrieren, dann Keycloak anschließen.**

| Benutzer | Herkunft | Ergebnis | Gruppen danach |
|---|---|---|---|
| `dora`, `anna` | migriert und in Keycloak | HTTP 409, `Username already exists` | unverändert lokal, keine Anmeldung möglich |
| `zoe`, `yusuf` | nur in Keycloak | Anmeldung erfolgreich, Konto mit `auth_provider = oidc` | keine, obwohl Keycloak `team-data` und `team-payments` meldet |

Die Ursachen stehen im Quelltext. Benutzer werden nur über `external_id` und Anbieter gefunden, anschließend scheitert das Anlegen an der eindeutigen Spalte `username` (`auth_service.rs:3595`). Gruppen werden nur innerhalb des eigenen Namensraums wiederverwendet. Das ist Absicht und schützt davor, dass ein Name aus dem Verzeichnis einen Benutzer in eine privilegierte lokale Gruppe bringt (`sso.rs:1792`, Issue 2759). Eine API zum Verknüpfen gibt es nicht: `UpdateUserRequest` kennt weder `auth_provider` noch `external_id`, `CreateGroupRequest` kein `external_source`.

**Reihenfolge 2: Erst Gruppen über die Anmeldung entstehen lassen, dann nur Rechte migrieren.**

| Schritt | Ergebnis |
|---|---|
| Lokale Benutzer und Gruppen entfernen, außer technischen Konten | Die Rechte gelöschter Principals bleiben als verwaiste Regeln zurück (11 von 13). `idp-cleanup.py` löscht sie deshalb zuerst, geprüft in [Lokale Konten und Aufräumen](#lokale-konten-und-aufräumen). |
| Technischer Benutzer `group-seed` aus allen Gruppen meldet sich einmal an | 6 Gruppen mit `external_source = oidc` entstehen sofort |
| `migrate.yml --tags security -e artifactory_migration_identity_mode=idp` | 7 Regeln auf die neuen Gruppen, unverändert blieb die lokale Gruppe `ci-robots` |
| `dora`, `zoe`, `yusuf`, `rita`, `anna` melden sich an | alle erfolgreich und mit den richtigen Gruppen |
| `anna` in `platform-admins` | `is_admin = true` durch `OIDC_ADMIN_GROUP` |

Zugriff mit dem API Token des jeweiligen Benutzers, denn Konten aus dem Identitätsanbieter haben kein Passwort:

| Vorgang | Ergebnis |
|---|---|
| `zoe` (`team-data`) Pull `docker-base/alpine:3.21.3` | erlaubt |
| `zoe` (`team-data`) Pull `docker-prod/web/nginx:1.27.4-alpine` | verweigert |
| `dora` (`team-payments`) Pull `docker-base/alpine:3.21.3` | erlaubt |
| `dora` (`team-payments`) Pull `docker-prod/web/nginx:1.27.4-alpine` | verweigert |
| `yusuf` (`release-managers`) Pull und Push auf `docker-prod` | erlaubt |
| `rita` (`security-auditors`) Pull `docker-prod/data/redis:7.4.2-alpine` | erlaubt |
| `rita` (`security-auditors`) Push nach `docker-prod` | verweigert, `You do not have access to this repository` |

**Entzug von Rechten.** `zoe` wurde in Keycloak aus `team-data` entfernt.

| Zeitpunkt | Pull `docker-base/alpine:3.21.3` mit vorhandenem Token |
|---|---|
| direkt nach dem Entfernen | **erlaubt** |
| nach der nächsten Anmeldung von `zoe` | verweigert |

Die Mitgliedschaft wird bei OIDC nur während der Anmeldung abgeglichen. Ein ausgeschiedener Mitarbeiter mit API Token behält seine Rechte, bis jemand eingreift. Für LDAP beschreibt `.env.example` einen regelmäßigen Abgleich (`LDAP_SYNC_INTERVAL`), getestet wurde er nicht. Der Austrittsprozess muss deshalb das Konto in Artifact Keeper deaktivieren oder seine Tokens widerrufen.

### Lokale Konten und Aufräumen

Sobald ein Anbieter aktiv ist, gilt für lokale Konten eine feste Regel im Code (`backend/src/api/handlers/auth.rs:253`). Der Test lief mit dem technischen Konto `ci-data` (Gruppe `ci-robots`) und mit noch nicht geändertem Einmalpasswort.

| Vorgang | Ergebnis |
|---|---|
| Administrator meldet sich lokal an | HTTP 200. Dieser Notzugang lässt sich mit `SSO_DISABLE_ADMIN_BREAK_GLASS` abschalten. |
| `ci-data` meldet sich lokal an | HTTP 401, `Local login is disabled when SSO is configured` |
| `ci-data` Pull `docker-base` mit Passwort über die Registry | **erlaubt** |
| `ci-data` Pull `docker-prod` mit Passwort über die Registry | verweigert, das Konto hat dort kein Recht |
| Administrator stellt für `ci-data` ein Token aus | erfolgreich |
| `ci-data` Pull `docker-base` mit diesem Token | erlaubt |

Daraus folgt: Lokale Konten können bei aktivem Anbieter weder die Oberfläche nutzen noch ihr Einmalpasswort selbst ändern. Die Registry nimmt das Passwort aber weiter an. Technische Konten sollten deshalb nur Tokens nutzen, die ein Administrator ausstellt, und das Einmalpasswort sollte nicht im Umlauf bleiben.

Ein Token wird je nach Schnittstelle unterschiedlich übergeben. Die Registry erwartet es als Passwort, also als `benutzer:token`. Die REST API erwartet `Authorization: Bearer <token>` und antwortet auf Basic Auth mit 401.

`idp-cleanup.py` wurde mit einem eigens angelegten Benutzer und einer Gruppe mit je einer Regel geprüft:

| Schritt | Regeln gesamt | Regeln der Testobjekte | ohne vorhandenen Principal |
|---|---|---|---|
| vorher | 23 | 2 | 11 |
| ohne `--apply` | 23 | 2 | 11 |
| mit `--apply` | 21 | 0 | 11 |

Die 11 Regeln ohne Principal stammen aus dem ersten Durchlauf, bevor das Skript Regeln mitlöschte. Sie blieben im Labor stehen und wären sonst über `DELETE /api/v1/permissions/<id>` zu entfernen.

### Mehrere Targets für dieselbe Gruppe

Rechte addieren sich in Artifactory über alle Targets. Artifact Keeper erlaubt je Gruppe und Repository nur eine Regel. Zwei Targets gaben `team-payments` auf `generic-tools` das Recht READ und READ mit WRITE. Das Playbook legte daraus eine Regel an.

| Prüfung | Ergebnis |
|---|---|
| Regeln auf `generic-tools` | 1, mit `read` und `write` |
| `dora` (`team-payments`) lädt eine Datei hoch | HTTP 201 |
| `dora` lädt die Datei herunter | HTTP 200 |
| `rita` (`security-auditors`) liest die Datei | HTTP 404 |
| `rita` lädt hoch | HTTP 403 |
| zweiter Lauf des Playbooks | keine Änderung |

Eine schon vorhandene Regel wird nicht erweitert. Kommt in der Quelle später ein Recht hinzu, muss die alte Regel erst gelöscht werden. Das Playbook prüft bei bestehenden Regeln nur, ob es sie gibt.

## Empfohlener Ablauf mit Identitätsanbieter

Dieser Ablauf gilt, wenn die Benutzer schon in einem Verzeichnis liegen, was bei einer lizenzierten Instanz mit LDAP oder SAML der Regelfall ist.

1. Client im Identitätsanbieter anlegen, den Claim `groups` mit einfachen Namen ausgeben (bei Keycloak `full.path` auf `false`).
2. Artifact Keeper verbinden: `OIDC_*` setzen, `OIDC_MAP_GROUPS_TO_GROUPS=true`, `OIDC_ADMIN_GROUP` festlegen. Die Adresse des Anbieters gehört in `AK_SSRF_ALLOW_PRIVATE_CIDRS`.
3. Artefakte wie in [03](03-migration.md) migrieren.
4. **Keine** lokalen Benutzer und Gruppen für Personen anlegen, die aus dem Verzeichnis kommen.
5. Technischen Benutzer in allen betroffenen Gruppen einmal anmelden, außer in der Administratorgruppe. Sonst erhält er Administratorrechte, wie im Test zu sehen war.
6. Rechte übertragen: `migrate.yml --tags security -e artifactory_migration_identity_mode=idp`. Die gemeldeten Regeln mit Pfadmustern fachlich lösen.
7. Den technischen Benutzer entfernen.
8. Technische Konten für Pipelines bleiben lokal. Ihre Tokens stellt ein Administrator aus, weil diese Konten sich nicht mehr anmelden können.
9. Den Austrittsprozess um das Deaktivieren in Artifact Keeper ergänzen.

Liegt schon eine Migration mit lokalen Konten vor, müssen diese vorab entfernt werden: `tools/evidence/idp-cleanup.py` zeigt ohne `--apply` nur an, was betroffen wäre. Die Kennung `sub` des Anbieters muss stabil bleiben. Ändert sie sich, etwa weil ein Realm neu angelegt wird, findet Artifact Keeper den Benutzer nicht mehr und das Anlegen scheitert am Namen. Das ergibt sich aus dem Quelltext und wurde nicht eigens getestet.

## Nachstellen

Quelltext prüfen. Das braucht nur `git` und Netz und verändert nichts:

```bash
tools/evidence/source-check.sh v1.11.11
```

Datenbank prüfen, auf dem Patroni Leader. Das Skript rollt alle Änderungen zurück:

```bash
sudo -u postgres psql -d artifact_registry -f tools/evidence/database-check.sql
```

Testdaten, Migration, Gruppen und Zugriffsmatrix:

```bash
ansible-playbook -i inventories/natnetwork/hosts.yml playbooks/jcr_seed.yml
ansible-playbook -i inventories/natnetwork/hosts.yml playbooks/migrate.yml --tags artifacts,verify,verify_images,security,verify_access
```

Reihenfolge 1 mit Keycloak, also die Konflikte. `ak-mgmt` braucht dafür 2 GB RAM:

```bash
ansible-playbook -i inventories/natnetwork/hosts.yml playbooks/keycloak.yml
ansible-playbook -i inventories/natnetwork/hosts.yml playbooks/artifact_keeper.yml -e ak_oidc_enabled=true
AK_URL=http://10.0.10.250 AK_PUBLIC_URL=http://localhost:30090 IDP_PASSWORD=<aus dem Vault> tools/evidence/oidc-login.py dora
```

Reihenfolge 2 mit Keycloak:

```bash
AK_URL=http://10.0.10.250 AK_ADMIN_PASSWORD=<aus dem Vault> tools/evidence/idp-cleanup.py --users dora,anna,zoe,yusuf,rita --groups team-payments,platform-admins,team-data,release-managers,security-auditors,team-checkout --apply
AK_URL=http://10.0.10.250 AK_PUBLIC_URL=http://localhost:30090 IDP_PASSWORD=<aus dem Vault> tools/evidence/oidc-login.py group-seed
ansible-playbook -i inventories/natnetwork/hosts.yml playbooks/migrate.yml --tags security -e artifactory_migration_identity_mode=idp
tools/evidence/oidc-scenario.sh inventories/natnetwork/group_vars/all/vault.yml
tools/evidence/rights-check.sh inventories/natnetwork/group_vars/all/vault.yml 10.0.10.6
```

## Nicht geprüft

| Thema | Stand |
|---|---|
| Lizenziertes Artifactory Pro oder Enterprise als Quelle | nicht verfügbar. Gruppen und Rechte wurden auf JCR und OSS geprüft. |
| LDAP und SAML | nur aus Quelltext und Dokumentation bekannt, nicht getestet |
| Anmeldung im Browser über die Weboberfläche | nicht getestet, nur der gleichwertige Ablauf per Skript |
| Rechte beim Zugriff über virtuelle Repositories | nicht getestet |
