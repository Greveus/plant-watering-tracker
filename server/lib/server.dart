import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'auth_middleware.dart';
import 'db/server_database.dart';
import 'handlers/health_handler.dart';
import 'handlers/photo_handler.dart';
import 'handlers/sync_handler.dart';
import 'photo_store.dart';

Future<HttpServer> run() async {
  final dbPath = Platform.environment['SYNC_DB_PATH'] ?? 'sync.db';
  final token = Platform.environment['SYNC_TOKEN'];
  if (token == null || token.isEmpty) {
    stderr.writeln('SYNC_TOKEN Umgebungsvariable ist nicht gesetzt.');
    exit(1);
  }

  final db = ServerDatabase.open(dbPath);
  final syncHandler = SyncHandler(db);
  final photosDir = Platform.environment['SYNC_PHOTOS_PATH'] ?? 'photos';
  final photoHandler = PhotoHandler(db, ServerPhotoStore(Directory(photosDir)));

  final router = Router()
    ..get('/health', handleHealth)
    ..post('/sync', syncHandler.call)
    ..put('/plants/<id>/photo', photoHandler.upload)
    ..get('/plants/<id>/photo', photoHandler.download);

  final pipeline = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(authMiddleware(expectedToken: token))
      .addHandler(router.call);

  final port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;
  final server = await shelf_io.serve(pipeline, InternetAddress.anyIPv4, port);
  print('plant-watering-sync-server läuft auf Port ${server.port} (DB: $dbPath)');
  return server;
}
