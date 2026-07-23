# Plant Watering Tracker – Sync-Server

Optionaler, eigenständiger Sync-Server für die [Plant Watering Tracker](https://github.com/Greveus/plant-watering-tracker) App. Ermöglicht das gemeinsame Nutzen derselben Räume/Pflanzen/Gieß-Historie durch mehrere Geräte im selben lokalen Netzwerk.

## Wichtig

- Die App bleibt **jederzeit vollständig offline nutzbar** – dieser Server ist rein ergänzend, kein Pflicht-Backend.
- Gedacht für den Betrieb **ausschließlich im eigenen Heim-Netzwerk** (kein Port-Forwarding, kein Internet-Zugriff von außen).
- Gieß-Events werden rein additiv gemergt (nie überschrieben/gelöscht). Räume/Pflanzen nutzen Last-Write-Wins per Zeitstempel. Löschungen sind Soft-Deletes (Tombstones).
- Die Bayes-Berechnung für die Gieß-Vorhersage läuft komplett lokal auf jedem Gerät – der Server speichert nur Rohdaten.

## Stack

Dart, [`shelf`](https://pub.dev/packages/shelf) + [`shelf_router`](https://pub.dev/packages/shelf_router), [`sqlite3`](https://pub.dev/packages/sqlite3) (kein Drift server-seitig).

## Setup

1. `.env` anlegen mit einem zufälligen Token:
   ```bash
   echo "SYNC_TOKEN=$(openssl rand -hex 16)" > .env
   ```
2. Container starten:
   ```bash
   docker compose up -d
   ```
3. In der App unter *Einstellungen → Server-Synchronisation* die Server-Adresse (z. B. `http://<hostname>.local:8080`, unbedingt den `.local`-mDNS-Namen statt einer reinen IP verwenden – sonst blockiert iOS die Verbindung) und den Token aus `.env` eintragen.

### Build-Hinweis

Falls der Server ohne Docker gebaut werden soll: `dart build cli` verwenden, **nicht** `dart compile exe` – das `sqlite3`-Package nutzt Native-Assets/Build-Hooks, die `dart compile exe` nicht unterstützt.

## Auth

Bearer-Token (`SYNC_TOKEN` env var) – jedes Gerät braucht denselben Token wie ein gemeinsames Passwort nur für den Sync.
