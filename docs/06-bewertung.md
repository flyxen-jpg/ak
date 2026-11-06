# 06 Bewertung: Artifact Keeper im professionellen Einsatz

[Zurück: Testprotokoll](05-testprotokoll.md) | [Übersicht](README.md) | [Weiter: Betriebshandbuch](07-betrieb.md)

In den Tabellen bedeutet „getestet“, dass die Aussage im Labor geprüft wurde. „Laut Dokumentation“ heißt, dass sie aus der Dokumentation oder dem Code des Herstellers stammt und nicht getestet wurde.

## Gesamturteil

Die Bewertung beantwortet die Frage des Auftrags: Kann Artifact Keeper eine lizenzierte Artifactory Instanz ablösen? Das Ergebnis ist ein Ja mit Vorbehalten. Artifact Keeper ist technisch reif genug für den produktiven Einsatz als Artefakt Repository. Bei Migration der Rechte, Rechtemodell und Produktreife gibt es Einschränkungen, die bewusst einzuplanen sind. Eine lizenzierte Instanz stand im Test nicht zur Verfügung, ihre Editionsmerkmale stammen aus der Dokumentation von JFrog.

Diese Stärken haben sich im Labor bestätigt:

* Echte Hochverfügbarkeit ohne Lizenzkosten. Der Cluster läuft aktiv/aktiv, alle Ausfälle heilten sich selbst, Rolling Updates liefen ohne einen einzigen Fehler. Bei JFrog gibt es Hochverfügbarkeit nur mit Enterprise Lizenz.
* Geringer Ressourcenbedarf. Das Backend braucht etwa 40 MB RAM, Artifactory OSS etwa 3,6 GB.
* Datenintegrität. Alle 449 migrierten Artefakte waren bitgenau, auch nach zehn Ausfallszenarien. Aus JFrog Container Registry kamen 24 von 24 Produktionsimages mit identischem Digest an.
* Identitätsanbieter ohne Lizenz. OIDC mit Keycloak funktionierte einschließlich Gruppenspiegelung und Administratorvergabe. Bei JFrog gibt es SAML laut Matrix ab Pro X und OAuth erst ab Enterprise X.
* Vernünftige Sicherheitsvorgaben: SSRF Schutz, Rate Limits, 404 statt 403 bei fehlendem Leserecht, erzwungener Passwortwechsel und keine Swagger Oberfläche im Produktionsmodus.
* Automatisierbarkeit. Das Ansible Projekt baut den gesamten Cluster reproduzierbar auf, auch ohne Internetzugang.

Diese Schwächen haben sich gezeigt:

* Die Migration ist unvollständig. Benutzer, Gruppen und Rechte werden trotz Ankündigung in der Dokumentation nicht migriert, der Code dafür wird nie aufgerufen und wäre auch nicht lauffähig. Gradle Repositories, Mitglieder virtueller Repositories, Remote Cache, Properties und Löschungen fehlen ebenfalls. Belege in [12](12-rechte-und-identitaeten.md).
* Das Rechtemodell ist gröber als bei Artifactory. Es kennt weder Pfadmuster noch Rechte auf Builds und Release Bundles.
* Lokale Konten und Identitätsanbieter lassen sich nicht verknüpfen. Ein migriertes Konto blockiert die Anmeldung über OIDC mit HTTP 409, eine migrierte Gruppe die Mitgliedschaft. Die Reihenfolge der Einführung ist deshalb entscheidend.
* Der Entzug einer Gruppe in Keycloak wirkt erst bei der nächsten Anmeldung. Vorhandene API Tokens behalten bis dahin ihre Rechte.
* Die Produktreife hält noch nicht mit. Artifact Keeper steht bei Version 1.x mit mehreren Releases pro Woche. Die Dokumentation ist stellenweise falsch oder widersprüchlich, und Details für den Clusterbetrieb wie Replikas in OpenSearch, Fehlercodes beim Datenbankausfall oder das Format der Schlüssel muss man selbst herausfinden.

## Funktionsvergleich

| Kriterium | Artifact Keeper 1.11.11 | JCR und OSS 7.161 | Artifactory Pro und Enterprise (laut JFrog, nicht getestet) |
|---|---|---|---|
| Lizenz und Kosten | MIT, kostenlos | kostenlos, eingeschränkt | kommerziell |
| Hochverfügbarkeit | aktiv/aktiv, getestet | nicht verfügbar | nur Enterprise |
| Formate | laut Dokumentation etwa 40. Getestet wurden Maven, Generic, Docker und Helm. | JCR: Docker, OCI, Helm, Generic. OSS: Maven, Gradle, Ivy, SBT, Generic | alle |
| Docker und OCI Registry | getestet mit 24 Images, auch Multi Arch | nur JCR | ja |
| Remote und virtuelle Repositories | Remote mit Pull Through getestet, virtuelle nach der Migration ohne Mitglieder | ja | ja |
| REST API für die Administration | vollständig, getestet | Repositories, Benutzer und Rechte gesperrt, HTTP 400 getestet | ja |
| Identitätsanbieter | OIDC mit Keycloak getestet. LDAP und SAML laut Dokumentation. | nur LDAP | LDAP Gruppen und SAML ab Pro X, OAuth ab Enterprise X, SCIM ab Enterprise X |
| Rechtemodell | Regel aus Principal, Repository und Aktionen, optional mit IP Bedingung, getestet | Permission Targets mit Pfadmustern, getestet | zusätzlich weitere Ressourcen, Rollen |
| Sicherheitsscans | laut Dokumentation Trivy, Grype, OpenSCAP und Dependency Track integriert | nein | Xray als Zusatzprodukt |
| Replikation zwischen Standorten | laut Dokumentation als Peer Mesh | nein | ja |
| Migration aus Artifactory | Artefakte im Betrieb mit Delta Läufen, getestet. Rechte fehlen, Playbook vorhanden. | | |
| Ressourcenbedarf | sehr gering (Rust) | hoch (Java, etwa 3,6 GB) | hoch |
| Automatisierte Installation | Ansible Projekt online und offline getestet | | |
| Support | Community über GitHub | Community | Hersteller mit SLA |

## Reifegrad

| Aspekt | Beobachtung |
|---|---|
| Version und Takt | Version 1.11.11 vom 3. November 2026, teils mehrere Releases pro Woche. Fehler werden schnell behoben, das Änderungstempo ist aber hoch. Versionen sollten fest eingetragen und Updates über eine Staging Umgebung eingespielt werden. |
| Community | etwa 1.200 Sterne auf GitHub, rund 170 Forks und 130 offene Issues, MIT Lizenz |
| Dokumentation | umfangreich, aber nicht immer zuverlässig. Die Migration der Berechtigungen wird als Funktion beschrieben, ist aber nicht umgesetzt. Variablennamen weichen voneinander ab (`DB_POOL_SIZE` und `DATABASE_MAX_CONNECTIONS`, `AWS_*` und `S3_*`). Das geforderte Format der Schlüssel (Base64 von genau 32 Byte) steht nicht in der Dokumentation. Die verlässlichste Quelle ist `.env.example`. |
| Codequalität | ausführliche Kommentare mit Verweisen auf Issues und viele Tests. Einzelne Funktionen wie `migrate_users` sind toter Code. |
| Unabhängigkeit vom Hersteller | Open Source eines einzelnen Anbieters ohne kommerziellen Support. Gibt das Projekt auf, bleibt dank MIT Lizenz ein Fork möglich. |

## Risiken und Gegenmaßnahmen

| Risiko | Auswirkung | Maßnahme |
|---|---|---|
| unvollständige Migration der Rechte | Nach dem Umzug fehlen Rechte. | `playbooks/migrate.yml`, Zugriffsmatrix mit eigenen Fällen, siehe [12](12-rechte-und-identitaeten.md) |
| Konto der Quelle sieht nicht alles | Der Job meldet Erfolg, Repositories fehlen. | Das Playbook vergleicht die Liste und bricht ab, siehe [13](13-airgap-zwei-vms.md) |
| lokale Konten kollidieren mit dem Identitätsanbieter | Anmeldung scheitert mit 409, Gruppen bleiben leer. | Reihenfolge aus [12](12-rechte-und-identitaeten.md) einhalten, `artifactory_migration_identity_mode: idp` |
| Entzug wirkt erst bei der nächsten Anmeldung | Ausgeschiedene behalten über Tokens Zugriff. | Austrittsprozess um Deaktivierung und Widerruf der Tokens ergänzen |
| Remote Cache wird nicht migriert | Nicht mehr beim Upstream verfügbare Images gehen verloren. | Solche Images vorab in ein lokales Repository kopieren |
| Quelle ist eine lizenzierte Instanz, getestet wurde JCR und OSS | Abweichungen sind nicht auszuschließen. | Probelauf gegen eine Kopie der eigenen Instanz |
| keine Pfadmuster in Rechten | Rechte werden gröber oder fehlen. | Repositories fachlich schneiden, zum Beispiel ein eigenes Repository für `isos/` |
| keine Replikas in OpenSearch | Die Suche fällt bei einem Knotenausfall aus. | Index Template mit Replikas, im Ansible Projekt enthalten |
| 401 statt 503 beim Datenbankausfall | scheinbare Login Fehler, möglicherweise Kontosperren | TTL von Patroni senken, Überwachung einrichten, Issue beim Projekt melden |
| schnelle Folge von Releases | unerwartete Änderungen | Versionen fest eintragen, Staging Cluster, Upgrades mit dem Ansible Projekt testen |
| kein Herstellersupport | Eskalation nur über die Community | eigenes Betriebswissen aufbauen, Wartungsvertrag mit einem Dienstleister prüfen |
| viele Abhängigkeiten | PostgreSQL mit Hochverfügbarkeit, S3 und OpenSearch müssen selbst betrieben werden. | vorhandene Plattformen nutzen wie Managed PostgreSQL oder unternehmenseigenes S3, sonst das Ansible Projekt |

## Wann passt Artifact Keeper?

Gut geeignet ist Artifact Keeper in diesen Fällen:

* bei Kostendruck durch die Lizenz von Artifactory Pro oder Enterprise, wenn deren Spezialfunktionen nicht gebraucht werden
* für Teams mit Erfahrung im Betrieb von Linux, PostgreSQL und S3 oder mit einer vorhandenen Plattform aus Kubernetes, Managed Database und S3
* wenn Identitäten ohnehin aus einem Verzeichnis kommen und Rechte auf Ebene der Repositories genügen

Sorgfältig prüfen sollte man in diesen Fällen:

* bei komplexen Rechtemodellen in Artifactory mit vielen Pfadmustern
* in Umgebungen, die vertraglich Herstellersupport mit SLA verlangen
* bei starker Nutzung von Enterprise Funktionen wie Xray Policies, Federation, Build Promotion oder Distribution. Diese wurden im Labor nicht geprüft, ein gleichwertiger Ersatz ist nicht belegt.

## Empfehlung

1. Einen Pilot mit einem Teilbereich starten, etwa einem Team mit Docker und Helm, auf einem Staging Cluster wie in diesem Labor. Das Ansible Projekt baut ihn reproduzierbar auf.
2. Vor der Entscheidung prüfen: einen Probelauf gegen eine Kopie der lizenzierten Instanz, weitere genutzte Formate wie npm und PyPI, die Anbindung an das eigene Verzeichnis, eine Probe für Backup und Restore sowie ein Upgrade über zwei Versionen von Artifact Keeper. Den Vertrag so kündigen, dass die Lizenz bis zum Ende der Rückfallfrist läuft.
3. Die Migration nach dem Vorgehen in [03](03-migration.md) durchführen, die Rechte nach [12](12-rechte-und-identitaeten.md).
4. In der Produktion drei vollwertige Knoten oder zwei Knoten mit Witness einsetzen, PostgreSQL mit Patroni oder als Managed Database, unternehmenseigenes S3, durchgängig TLS und Überwachung von `/readyz`, den Statistiken von HAProxy, Patroni und dem Zustand von OpenSearch.
