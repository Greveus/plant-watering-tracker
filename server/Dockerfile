# Stage 1: Build — dart build cli statt dart compile exe, da das sqlite3-
# Package ein natives Build-Hook (code_assets) nutzt, das "dart compile exe"
# nicht unterstützt ("dart compile does not support build hooks").
FROM dart:stable AS build
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get
COPY . .
RUN dart pub get --offline
RUN dart run build_runner build --delete-conflicting-outputs
RUN dart build cli -o /app/out --target bin/server.dart

# Stage 2: Runtime — schlankes Image, nur libsqlite3 als Laufzeit-Abhängigkeit.
# setpriv (util-linux) wird gebraucht, um im Entrypoint nach dem chown auf
# /data dauerhaft auf den unprivilegierten Dienstnutzer zu wechseln.
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    libsqlite3-0 wget util-linux \
    && rm -rf /var/lib/apt/lists/*

# Unprivilegierter Dienstnutzer: der Server braucht Schreibrechte auf /data,
# sonst nichts. Feste UID, damit der Besitz eines bestehenden Host-Volumes
# über Image-Neubauten hinweg stabil bleibt.
RUN useradd --system --uid 10001 --user-group --no-create-home syncsrv

COPY --from=build /app/out/bundle /app
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh && chown -R syncsrv:syncsrv /app

EXPOSE 8080
VOLUME /data
ENV SYNC_DB_PATH=/data/sync.db
ENV SYNC_PHOTOS_PATH=/data/photos
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh", "/app/bin/server"]
