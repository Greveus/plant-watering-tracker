#!/bin/sh
# Der Container startet als root, damit das gemountete /data-Volume dem
# Dienstnutzer zugeordnet werden kann – ein chown im Dockerfile greift dafür
# nicht, weil der Mount erst zur Laufzeit darüberliegt. Ohne diesen Schritt
# müsste jede Bestandsinstallation den Besitz auf dem Host von Hand anpassen,
# sonst startet der Server nach dem Update nicht mehr.
#
# Danach wird die Privilegierung dauerhaft abgegeben: der Dart-Server selbst
# läuft als unprivilegierter Nutzer, damit eine künftige Lücke im Server nicht
# gleich Rootrechte im Container bedeutet.
set -e

mkdir -p /data
chown -R syncsrv:syncsrv /data

exec setpriv --reuid=syncsrv --regid=syncsrv --init-groups "$@"
