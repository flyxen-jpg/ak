# 06 Bewertung: Artifact Keeper im professionellen Einsatz

[Zurück: Testprotokoll](05-testprotokoll.md) | [Übersicht](README.md) | [Weiter: Betriebshandbuch](07-betrieb.md)

In den Tabellen bedeutet „getestet“, dass die Aussage im Labor geprüft wurde. „Laut Dokumentation“ heißt, dass sie aus der Dokumentation oder dem Code des Herstellers stammt und nicht getestet wurde.

## Gesamturteil

Artifact Keeper ist technisch reif genug für den produktiven Einsatz als Artefakt-Repository. Bei Migration, Rechtemodell und Produktreife gibt es Einschränkungen, die man bewusst einplanen muss.

Diese Stärken haben sich im Labor bestätigt:

* Echte Hochverfügbarkeit ohne Lizenzkosten. Der Cluster läuft aktiv/aktiv, alle Ausfälle heilten sich selbst, Rolling Updates liefen ohne einen einzigen Fehler. Bei JFrog gibt es Hochverfügbarkeit nur mit Enterprise-Lizenz.
* Geringer Ressourcenbedarf. Das Backend braucht etwa 40 MB RAM, Artifactory OSS etwa 3,6 GB.
* Datenintegrität. Alle 449 migrierten Artefakte waren bitgenau, auch nach zehn Ausfallszenarien.
* Vernünftige Sicherheitsvorgaben: SSRF-Schutz, Rate Limits, 404 statt 403 bei fehlendem Leserecht, erzwungener Passwortwechsel und keine Swagger-Oberfläche im Produktionsmodus.
* Automatisierbarkeit. Das Ansible-Projekt baut den gesamten Cluster reproduzierbar auf, auch ohne Internetzugang.

Diese Schwächen haben sich gezeigt:

* Die Migration ist unvollständig. User, Gruppen und Berechtigungen werden trotz Ankündigung in der Dokumentation nicht migriert. Gradle-Repositories, die Mitglieder virtueller Repositories und Löschungen fehlen.
* Das Rechtemodell ist gröber als bei Artifactory, es kennt keine Pfadmuster.
* Die Produktreife hält noch nicht mit. Artifact Keeper steht bei Version 1.x mit mehreren Releases pro Woche. Die Dokumentation ist stellenweise falsch oder widersprüchlich, und Details für den Clusterbetrieb wie Replikas in OpenSearch, Fehlercodes beim Datenbankausfall oder das Format der Schlüssel muss man selbst herausfinden.

## Funktionsvergleich

| Kriterium | Artifact Keeper 1.11.11 | Artifactory OSS 7.161 | Artifactory Pro und Enterprise |
|---|---|---|---|
| Lizenz und Kosten | MIT, kostenlos | kostenlos, eingeschränkt | kommerziell |
| Hochverfügbarkeit | aktiv/aktiv, getestet | nicht verfügbar | nur Enterprise |
| Formate | laut Dokumentation etwa 40 (Maven, npm, PyPI, NuGet, Cargo, Go, Helm, Debian, RPM, Alpine, OCI und Docker, Conan, Conda, Terraform und weitere). Getestet wurden Maven und Generic. | Maven, Gradle, Ivy, SBT, Generic | alle |
| Docker- und OCI-Registry | laut Dokumentation ja | nein, nur in JCR und Pro | ja |
| Remote- und virtuelle Repositories | Remote mit Pull-Through getestet, virtuelle nach der Migration ohne Mitglieder | ja | ja |
| REST-API für die Administration | vollständig, getestet | Repositories, User und Rechte nur in Pro | ja |
| SSO | laut Dokumentation OIDC, LDAP und SAML | nein, LDAP nur in Pro | ja |
| Rechtemodell | Repository und Aktion, optional mit IP-Bedingung, getestet | Permission Targets mit Pfadmustern | wie OSS, zusätzlich Projekte |
| Sicherheitsscans | laut Dokumentation Trivy, Grype, OpenSCAP und Dependency-Track integriert | nein | Xray als Zusatzprodukt |
| Replikation zwischen Standorten | laut Dokumentation als Peer-Mesh | nein | ja |
| Migration aus Artifactory | Artefakte live mit Delta-Läufen, getestet. Berechtigungen fehlen. | | |
| Ressourcenbedarf | sehr gering (Rust) | hoch (Java, etwa 3,6 GB) | hoch |
| Automatisierte Installation | Ansible-Projekt online und offline getestet | | |
| Support | Community über GitHub | Community | Hersteller mit SLA |

## Reifegrad

| Aspekt | Beobachtung |
|---|---|
| Version und Takt | Version 1.11.11 vom 3. November 2026, teils mehrere Releases pro Woche. Fehler werden schnell behoben, das Änderungstempo ist aber hoch. Versionen sollten fest eingetragen und Updates über eine Staging-Umgebung eingespielt werden. |
| Community | etwa 1.200 Sterne auf GitHub, rund 170 Forks und 130 offene Issues, MIT-Lizenz |
| Dokumentation | umfangreich, aber nicht immer zuverlässig. Die Migration der Berechtigungen wird als Funktion beschrieben, ist aber nicht umgesetzt. Variablennamen weichen voneinander ab (`DB_POOL_SIZE` und `DATABASE_MAX_CONNECTIONS`, `AWS_*` und `S3_*`). Das geforderte Format der Schlüssel (Base64 von genau 32 Byte) steht nicht in der Dokumentation. Die verlässlichste Quelle ist `.env.example`. |
| Codequalität | ausführliche Kommentare mit Verweisen auf Issues und viele Tests. Einzelne Funktionen wie `migrate_users` sind toter Code. |
| Unabhängigkeit vom Hersteller | Open Source eines einzelnen Anbieters ohne kommerziellen Support. Gibt das Projekt auf, bleibt dank MIT-Lizenz ein Fork möglich. |

## Risiken und Gegenmaßnahmen

| Risiko | Auswirkung | Maßnahme |
|---|---|---|
| unvollständige Migration der Berechtigungen | Nach dem Umzug fehlen Rechte. | Identitäten über LDAP oder OIDC, Rechte neu konzipieren, eigenes Skript `lab/migration/migrate-security.sh` |
| keine Pfadmuster in Rechten | Rechte werden gröber oder fehlen. | Repositories fachlich schneiden, zum Beispiel ein eigenes Repository für `isos/` |
| keine Replikas in OpenSearch | Die Suche fällt bei einem Knotenausfall aus. | Index-Template mit Replikas, im Ansible-Projekt enthalten |
| 401 statt 503 beim Datenbankausfall | scheinbare Login-Fehler, möglicherweise Kontosperren | TTL von Patroni senken, Überwachung einrichten, Issue beim Projekt melden |
| schnelle Folge von Releases | unerwartete Änderungen | Versionen fest eintragen, Staging-Cluster, Upgrades mit dem Ansible-Projekt testen |
| kein Herstellersupport | Eskalation nur über die Community | eigenes Betriebswissen aufbauen, Wartungsvertrag mit einem Dienstleister prüfen |
| viele Abhängigkeiten | PostgreSQL mit Hochverfügbarkeit, S3 und OpenSearch müssen selbst betrieben werden. | vorhandene Plattformen nutzen wie Managed PostgreSQL oder unternehmenseigenes S3, sonst das Ansible-Projekt |

## Wann passt Artifact Keeper?

Gut geeignet ist Artifact Keeper in diesen Fällen:

* als Ablösung von Artifactory OSS oder JCR, wo Hochverfügbarkeit, SSO, Docker und eine vollständige REST-API fehlen
* für Teams mit Erfahrung im Betrieb von Linux, PostgreSQL und S3 oder mit einer vorhandenen Plattform aus Kubernetes, Managed Database und S3
* bei Kostendruck durch Artifactory Pro oder Enterprise, wenn deren Spezialfunktionen nicht gebraucht werden

Sorgfältig prüfen sollte man in diesen Fällen:

* bei komplexen Rechtemodellen in Artifactory mit vielen Pfadmustern
* in Umgebungen, die vertraglich Herstellersupport mit SLA verlangen
* bei starker Nutzung von Enterprise-Funktionen wie Xray-Policies, Federation, Build-Promotion oder Distribution. Diese wurden im Labor nicht geprüft, ein gleichwertiger Ersatz ist nicht belegt.

## Empfehlung

1. Einen Pilot mit einem Teilbereich starten, etwa einem Team mit Maven und Docker, auf einem Staging-Cluster wie in diesem Labor. Das Ansible-Projekt baut ihn reproduzierbar auf.
2. Vor der Entscheidung prüfen: weitere genutzte Formate wie npm, PyPI und Docker, die Anbindung an LDAP oder OIDC, eine Probe für Backup und Restore sowie ein Upgrade über zwei Versionen von Artifact Keeper.
3. Die Migration nach dem Vorgehen in [03](03-migration.md) durchführen, die Berechtigungen getrennt davon.
4. In der Produktion drei vollwertige Knoten oder zwei Knoten mit Witness einsetzen, PostgreSQL mit Patroni oder als Managed Database, unternehmenseigenes S3, durchgängig TLS und Überwachung von `/readyz`, den Statistiken von HAProxy, Patroni und dem Zustand von OpenSearch.
