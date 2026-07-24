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

# Stage 2: Runtime — schlankes Image, nur libsqlite3 als Laufzeit-Abhängigkeit
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends libsqlite3-0 wget \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/out/bundle /app
EXPOSE 8080
VOLUME /data
ENV SYNC_DB_PATH=/data/sync.db
ENV SYNC_PHOTOS_PATH=/data/photos
ENTRYPOINT ["/app/bin/server"]
