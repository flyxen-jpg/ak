# 1 Worum es geht

[Übersicht Grundlagen](README.md) | [Weiter: Netzwerk](02-netzwerk.md)

## Was ist ein Artefakt?

Ein Artefakt ist das fertige Ergebnis eines Bauvorgangs: ein Java Archiv, ein Python Paket, ein Container Image, ein Helm Chart. Quellcode liegt in Git. Das, was daraus gebaut und ausgeliefert wird, liegt in einem Artefakt Repository.

Das hat drei Gründe:

* **Wiederholbarkeit.** Eine Auslieferung nutzt genau die Datei, die vorher getestet wurde, und baut nicht neu.
* **Unabhängigkeit.** Fällt Docker Hub aus oder löscht jemand ein Paket im Internet, laufen die eigenen Builds weiter, weil eine Kopie im Haus liegt.
* **Kontrolle.** Es ist festgelegt, wer lesen und wer schreiben darf.

## Lokal, remote, virtuell

| Art | Bedeutung | Beispiel im Labor |
|---|---|---|
| lokal | Die Dateien liegen hier und werden hierher hochgeladen. | `docker-prod` |
| remote | Ein Zwischenspeicher für eine fremde Quelle. Beim ersten Abruf wird die Datei geholt und aufbewahrt. Das nennt man Pull Through. | `docker-hub` |
| virtuell | Ein gemeinsamer Name für mehrere Repositories. Clients müssen sich nur eine Adresse merken. | `docker-all` |

## Container Images, Tags und Digests

Ein Container Image besteht aus mehreren Schichten und einer Beschreibung, dem Manifest. Eine Registry ist ein Artefakt Repository für solche Images.

* Ein **Tag** ist ein lesbarer Name, etwa `nginx:1.27.4-alpine`. Er kann theoretisch später auf einen anderen Inhalt zeigen.
* Ein **Digest** ist ein Fingerabdruck (SHA-256) des Manifests, etwa `sha256:a71e...`. Ändert sich ein einziges Byte, ändert sich der Digest.

Deshalb ist der Digest der Nachweis einer korrekten Migration: Stimmt er auf beiden Seiten überein, ist das Manifest identisch, und das Manifest benennt wiederum alle Schichten über deren Digest. Produktionsimages nutzen feste Tags, damit klar ist, welche Version läuft. Ein Tag wie `latest` wäre dafür ungeeignet.

Ein **Multi Arch Image** enthält unter einem Tag mehrere Fassungen für verschiedene Prozessoren. Das Manifest ist dann eine Liste. `alpine:3.21.3` im Labor ist ein solches Image.

## Die beiden Produkte

**JFrog Artifactory** ist der etablierte kommerzielle Standard. Es gibt mehrere Editionen:

| Edition | Kosten | Inhalt |
|---|---|---|
| Artifactory OSS | kostenlos | Maven, Gradle und einige weitere, ohne Container |
| JFrog Container Registry (JCR) | kostenlos | Docker, OCI, Helm, Generic |
| Pro und Enterprise | Lizenz | alle Formate, weitere Identitätsanbieter, Hochverfügbarkeit nur bei Enterprise |

Eingesetzt wird heute eine lizenzierte Instanz. Für den Test stand sie nicht zur Verfügung, deshalb dienten OSS und JCR als Quelle.

**Artifact Keeper** ist eine junge Open Source Alternative unter MIT Lizenz, in Rust geschrieben. Das Programm selbst ist klein und sparsam, braucht aber weitere Dienste: PostgreSQL für Metadaten, einen Speicher für Dateien (S3) und OpenSearch für die Suche.

## Warum überhaupt ein Wechsel?

Das Ziel ist, von den Lizenzkosten und den Grenzen der Editionen wegzukommen. Der Preis dafür: Kein Hersteller steht in der Pflicht, und das Team trägt den Betrieb selbst. Die Bewertung steht in [Kapitel 06](../06-bewertung.md).
