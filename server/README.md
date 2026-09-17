# Plant Watering Tracker – Sync-Server

Optionaler, eigenständiger Sync-Server für die [Plant Watering Tracker](https://github.com/Greveus/plant-watering-tracker) App. Ermöglicht es, dieselben Räume, Pflanzen und die Gieß-Historie über mehrere Geräte im selben lokalen Netzwerk hinweg zu teilen (z. B. für zwei Personen im selben Haushalt).

## Wichtig zu wissen

- Die App bleibt **jederzeit vollständig offline nutzbar** – dieser Server ist rein ergänzend, kein Pflicht-Backend. Ohne ihn funktioniert die App normal, nur eben ohne geräteübergreifenden Abgleich.
- Gedacht für den Betrieb **ausschließlich im eigenen Heim-Netzwerk**. Kein Port-Forwarding, kein Internet-Zugriff von außen, keine TLS-Terminierung – der Server ist nicht für den Betrieb außerhalb eines vertrauenswürdigen lokalen Netzwerks gedacht.
- Gieß-Events werden rein additiv gemergt (nie überschrieben oder gelöscht). Räume und Pflanzen nutzen Last-Write-Wins per Zeitstempel. Löschungen sind Soft-Deletes (Tombstones) – nichts wird beim Sync endgültig gelöscht.
- Die Bayes-Berechnung für die Gieß-Vorhersage läuft komplett lokal auf jedem Gerät. Der Server speichert ausschließlich Rohdaten (Räume, Pflanzen, Gieß-Events) und rechnet selbst nichts.

## Voraussetzungen

- Ein Gerät, das dauerhaft im selben Heim-Netzwerk läuft wie die Smartphones, die synchronisieren sollen (z. B. NAS, Raspberry Pi, Homeserver, Mini-PC).
- [Docker](https://docs.docker.com/get-docker/) und Docker Compose auf diesem Gerät.
- mDNS/Bonjour im Netzwerk, damit `<hostname>.local` auflösbar ist (auf den meisten Heimroutern und Linux-Distributionen mit Avahi bereits Standard, macOS hat es eingebaut).

## Einrichtung

1. **Repo auf das Zielgerät bringen**, z. B. per `git clone` oder Kopieren des `server/`-Ordners.

2. **Token erzeugen** – ein zufälliges Passwort, das die Geräte beim Sync als Zugriffsnachweis mitschicken:
   ```bash
   cd server
   echo "SYNC_TOKEN=$(openssl rand -hex 16)" > .env
   ```
   Die Datei `.env` niemals committen oder weitergeben – wer den Token kennt, kann mitsynchronisieren.

3. **Container bauen und starten:**
   ```bash
   docker compose up -d --build
   ```
   Das baut ein schlankes Debian-Image (Dart-Server + `libsqlite3`), das dauerhaft läuft (`restart: unless-stopped`) und die Datenbank in `./data/sync.db` auf dem Host persistiert (Volume-Mount, überlebt also Container-Neustarts/-Updates).

4. **Erreichbarkeit prüfen:**
   ```bash
   curl http://localhost:8080/health
   ```
   sollte `ok` (oder einen 200er-Status) liefern. Von einem anderen Gerät im selben Netzwerk aus stattdessen den Hostnamen testen, z. B. `curl http://<hostname>.local:8080/health`.

5. **In der App eintragen** – unter *Einstellungen → Server-Synchronisation*:
   - **Server-Adresse**: `http://<hostname>.local:8080` – **unbedingt den `.local`-Namen verwenden, nicht die IP-Adresse** (siehe Hinweis unten, sonst blockiert iOS die Verbindung).
   - **Zugriffs-Token**: der Wert aus der `.env`-Datei (ohne das `SYNC_TOKEN=`-Präfix).
   - Mit *Verbindung testen* prüfen, dann *Speichern*.
   - Auf jedem weiteren Gerät, das mitsynchronisieren soll, dieselbe Adresse und denselben Token eintragen.

Nach dem Speichern erscheinen die Sync-Buttons (Dashboard-Icon, „Jetzt synchronisieren“ in den Einstellungen) automatisch – ohne konfigurierten Server bleiben sie ausgeblendet.

## Wichtige Einschränkung: iOS blockiert HTTP zu IP-Adressen

Der Server läuft bewusst nur über `http://` (kein sinnvolles TLS-Zertifikat für eine rein lokale Adresse möglich). iOS blockiert unverschlüsseltes HTTP standardmäßig, außer für lokale `.local`-mDNS-Namen (App Transport Security, `NSAllowsLocalNetworking`). Eine reine IP-Adresse wie `192.168.1.50` wird davon **nicht zuverlässig** erfasst – deshalb muss immer der `.local`-Hostname verwendet werden, sonst schlägt die Verbindung von iPhones/iPads aus fehl (Android ist davon nicht betroffen, funktioniert aber ebenso mit dem `.local`-Namen).

Den eigenen mDNS-Hostnamen findet man z. B. mit `hostname` (Linux/macOS) oder in der Router-Oberfläche unter den verbundenen Geräten.

## Server aktualisieren

```bash
git pull
docker compose up -d --build
```
Die Datenbank in `./data/` bleibt dabei erhalten.

## Server-Logs ansehen / Fehlersuche

```bash
docker compose logs -f
```
Health-Check-Status prüfen:
```bash
docker inspect --format='{{json .State.Health}}' plant-sync-server
```

### Häufige Fälle

- **Der Container startet endlos neu** (`docker compose ps` zeigt dauerhaft „Restarting"): Meist fehlt die `.env`-Datei oder `SYNC_TOKEN` ist darin leer. Der Server bricht dann absichtlich sofort ab, damit er nicht ungeschützt läuft – in Verbindung mit `restart: unless-stopped` sieht das nach einem Absturz aus. Die Ursache steht in `docker compose logs`.
- **Ein Gerät bekommt „Token abgelehnt"**: In den Logs erscheint eine `auth:`-Zeile mit dem Grund (falscher Token oder gar kein `Authorization`-Header). Token in der App unter *Einstellungen → Server-Synchronisation* mit dem Wert aus der `.env` abgleichen – ohne das `SYNC_TOKEN=`-Präfix.

## Sicherheit im Betrieb

Der Server läuft im Container als unprivilegierter Nutzer (`syncsrv`, UID 10001), nicht als root. Beim Start passt ein Entrypoint-Skript einmalig die Besitzrechte des gemounteten `./data`-Verzeichnisses an und gibt die Rootrechte danach dauerhaft ab – ein Update einer bestehenden Installation braucht dafür keinen manuellen Eingriff. Zusätzlich sind in `docker-compose.yml` alle Linux-Capabilities bis auf die für diesen Wechsel nötigen abgelegt und `no-new-privileges` gesetzt.

Das ersetzt keine Netzwerkabsicherung: Der Server hat weiterhin keine TLS-Verschlüsselung und keinen Schutz gegen wiederholte Anmeldeversuche. Er gehört ausschließlich in ein vertrauenswürdiges Heim-Netzwerk, ohne Port-Forwarding.

## Stack

Dart, [`shelf`](https://pub.dev/packages/shelf) + [`shelf_router`](https://pub.dev/packages/shelf_router), [`sqlite3`](https://pub.dev/packages/sqlite3) (kein Drift server-seitig, da keine reaktiven Streams benötigt werden).

### Build-Hinweis (nur relevant ohne Docker)

Falls der Server direkt gebaut werden soll: `dart build cli` verwenden, **nicht** `dart compile exe` – das `sqlite3`-Package nutzt Native-Assets/Build-Hooks, die `dart compile exe` nicht unterstützt ("dart compile does not support build hooks").

## Auth

Bearer-Token (`SYNC_TOKEN`-Umgebungsvariable) – jedes Gerät braucht denselben Token wie ein gemeinsames Passwort nur für den Sync. Der Token wird ausschließlich in der lokalen `.env`-Datei auf dem Server gespeichert, niemals im Repo.
