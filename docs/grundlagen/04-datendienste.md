# 4 Datendienste

[Zurück: Hochverfügbarkeit](03-hochverfuegbarkeit.md) | [Übersicht Grundlagen](README.md) | [Weiter: Container](05-container.md)

Artifact Keeper selbst merkt sich nichts dauerhaft. Das nennt man zustandslos, und genau deshalb können zwei Kopien gleichzeitig laufen. Die Daten liegen in drei spezialisierten Diensten.

| Dienst | Speichert | Beispiel | Geht er verloren |
|---|---|---|---|
| PostgreSQL | Metadaten | Wer darf was, welche Tags gibt es, welcher Digest gehört dazu | Das System weiß nicht mehr, was es hat. |
| Garage (S3) | Dateien | Schichten der Images, JAR Dateien | Der Inhalt fehlt. |
| OpenSearch | Suchindex | Suche nach Paketnamen | Die Suche fällt aus, der Index lässt sich neu aufbauen. |

## PostgreSQL und Replikation

PostgreSQL ist eine relationale Datenbank. Geschrieben wird nur auf einem Knoten, dem **Primary**. Er schickt jede Änderung fortlaufend an die **Replica**, die eine fast aktuelle Kopie hält (Streaming Replikation). Fällt der Primary aus, muss jemand die Replica befördern. Das ist die Aufgabe von Patroni.

## Patroni

**Patroni** überwacht PostgreSQL auf jedem Knoten und führt den Wechsel durch, den **Failover**. Der Primary muss seinen Führungsanspruch regelmäßig erneuern. Geschieht das nicht bis zum Ablauf einer Frist (TTL), übernimmt eine Replica. Diese TTL bestimmt im Wesentlichen die Dauer der Unterbrechung: Kürzer heißt schnelleres Umschalten, aber auch mehr Fehlalarme bei kurzen Netzstörungen.

Patroni bietet eine kleine Schnittstelle: `/primary` antwortet nur auf dem aktuellen Primary mit 200. So erkennt HAProxy, wohin es verbinden muss. `pg_rewind` bringt einen zurückgekehrten alten Primary wieder auf Stand, damit er als Replica weiterlaufen kann.

```bash
sudo patronictl -c /etc/patroni/patroni.yml list
```

zeigt, wer gerade welche Rolle hat. PostgreSQL läuft als normaler systemd Dienst und nicht im Container, damit die Datenbank unabhängig von der Container Umgebung bleibt.

## etcd

Patroni braucht einen neutralen Ort, an dem festgehalten ist, wer Primary ist. Das leistet **etcd**, eine kleine Datenbank für genau solche Absprachen. Fachlich heißt sie DCS (Distributed Configuration Store). etcd nutzt das Verfahren **Raft**: Ein Wert gilt erst, wenn die Mehrheit der drei Mitglieder ihn bestätigt hat. Damit kann es nie zwei Primaries geben, solange nur eine Seite die Mehrheit hat.

## S3 und Objektspeicher

Dateien in einer Datenbank abzulegen wäre unpraktisch. Ein normales Dateisystem liegt aber nur auf einem Rechner. **Objektspeicher** löst das: Dateien werden als Objekte in einem Bucket abgelegt und per HTTP geholt. **S3** ist die von Amazon stammende Schnittstelle dafür, inzwischen ein allgemeiner Standard.

Die Alternative NFS, ein Netzlaufwerk, wäre einfacher. Fällt aber der NFS Server aus, hängen alle Downloads. Das wurde getestet. NFS ist nur mit einem bereits hochverfügbaren NAS sinnvoll.

## Garage

**Garage** ist ein kleiner Open Source Objektspeicher für selbst betriebene Cluster. Hier speichert er jedes Objekt dreifach, je einmal pro Knoten, und bestätigt einen Schreibvorgang, sobald zwei von drei fertig sind. MinIO wäre die bekannte Alternative, veröffentlicht aber seit Ende 2025 keine Community Images mehr. In einem Unternehmen kommt ebenso ein vorhandener S3 Speicher infrage.

Garage kennt ein **Layout**, das festlegt, welcher Knoten welche Daten trägt. Die Rolle `garage` richtet Layout und Bucket ein und importiert den Zugangsschlüssel aus dem Vault.

## OpenSearch

**OpenSearch** ist eine Suchmaschine. Sie zerlegt Indizes in Shards und hält von diesen Kopien, die Replikas. Artifact Keeper legt seine Indizes ohne Replikas an. Fällt dann ein Knoten aus, fehlt ein Teil des Index. Die Rolle `opensearch` installiert deshalb ein **Index Template**, das jedem neuen Index eine Replika gibt. Diese Lücke wurde erst im Ausfalltest sichtbar.

Der Status `green` bedeutet, dass alle Kopien vorhanden sind. `yellow` heißt, dass Kopien fehlen, aber alle Daten erreichbar sind. `red` heißt, dass Daten fehlen.

## Warum nicht alles viel einfacher?

Das geht, und zwar als [Einzelknoten](../10-einzelknoten.md), dann ohne Ausfallsicherheit. Jeder zusätzliche Dienst ist auch ein Dienst, den jemand betreiben muss. Das ist der wahre Preis der Hochverfügbarkeit. Wer eine vorhandene Plattform mit verwalteter Datenbank und S3 hat, kann diese nutzen und spart sich Patroni, etcd und Garage.
