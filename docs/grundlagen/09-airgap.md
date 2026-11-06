# 9 Installieren ohne Internet

[Zurück: Anpassen](08-anpassen.md) | [Übersicht Grundlagen](README.md)

## Was Airgap bedeutet

Ein **Airgap**, wörtlich ein Luftspalt, bezeichnet ein Netz ohne Verbindung nach außen. Banken, Behörden und Industrieanlagen arbeiten oft so. Software kann dort nichts nachladen. Alles muss vorher geprüft und über einen Datenträger hineingebracht werden.

Das hat zwei Folgen. Wer von außen angreift, kommt schwerer hinein. Dafür fällt alles aus, was stillschweigend das Internet voraussetzt: Paketquellen, Container Registries, Zeitserver, Namensauflösung und Lizenzabfragen.

## Das Bundle

Ein **Bundle** ist ein Verzeichnis, das alles Nötige enthält. Es entsteht auf einem Rechner mit Internet und wandert dann über einen Datenträger in das isolierte Netz.

| Inhalt | Wozu | Woher sonst |
|---|---|---|
| RPM Pakete mit allen Abhängigkeiten | Betriebssystemteile wie Podman | Spiegelserver von Rocky Linux |
| Container Images als Archiv | die Anwendungen | Registries wie ghcr.io |
| Ansible Collections | Erweiterungen von Ansible | Ansible Galaxy |
| Prüfsummen | Beschädigung und Manipulation erkennen | nicht nötig |

Eine **Prüfsumme** ist der Fingerabdruck einer Datei. Ändert sich ein Bit, ändert sich der Fingerabdruck. Die Pakete tragen zusätzlich eine **Signatur** des Herstellers. Sie beweist, von wem ein Paket stammt, auch wenn der Datenträger unterwegs in falsche Hände geriet.

## Was im isolierten Netz fehlt und wie es ersetzt wird

| Es fehlt | Folge | Lösung im Projekt |
|---|---|---|
| Paketquellen | `dnf install` findet nichts. | Rolle `offline_repo` legt eine lokale Quelle aus dem Bundle an. |
| Registries | `podman pull` scheitert. | `podman load` lädt das Archiv, Units starten mit `Pull=never`. |
| Zeitserver | Die Uhren laufen auseinander, Tokens gelten dann nicht mehr. | Eine VM dient als Zeitgeber für die andere. Das ist nur für Tests sinnvoll, in Produktion gibt es interne Zeitserver. |
| Namensauflösung | Namen wie `ghcr.io` lassen sich nicht auflösen. | Die Inventories arbeiten mit IP Adressen. |

## Was restriktiv zusätzlich bedeutet

Viele Unternehmen verlangen über den Airgap hinaus **Härtung**, also das Abschalten von allem, was nicht gebraucht wird.

* **`noexec` auf `/tmp`:** Aus den temporären Verzeichnissen dürfen keine Programme starten, wo sich Schadcode gern ablegt.
* **`umask 027`:** Neue Dateien sind für andere Benutzer nicht lesbar.
* **SELinux:** Der Kernel erlaubt Prozessen nur, was ihre Regel vorsieht.
* **Firewall für den Ausgang:** Meist wird nur der Eingang gefiltert. Hier ist auch der Ausgang gesperrt, damit ein Programm selbst dann nichts nach außen senden kann, wenn jemand versehentlich ein Gateway einrichtet.

## Warum JFrog so viel Speicher braucht

Java Programme laufen in einer **JVM**, einer virtuellen Maschine, die sich ihren Speicher vom System holt. Der **Heap** ist der Bereich für die Daten des Programms. `-Xmx640m` begrenzt ihn auf 640 MB. Dazu kommt Speicher für den übersetzten Code und die Verwaltung, oft noch einmal mehrere Hundert MB.

JFrog besteht aus mehreren Programmen. Fünf davon sind eigene JVMs. Wer nur eine begrenzt, spart wenig. Reicht der Speicher nicht, lagert das System in den **Swap** auf die Platte aus, und alles wird langsam. Das ist der Grund, warum das Laden der Testdaten mit besseren Grenzen fast sechsmal schneller ging. Die Messungen stehen in [Kapitel 14](../14-jfrog-tuning.md).

## Weiterlesen

Den vollständigen Ablauf mit allen Befehlen beschreibt [Kapitel 13](../13-airgap-zwei-vms.md).
