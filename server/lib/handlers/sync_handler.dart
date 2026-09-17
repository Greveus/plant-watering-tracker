import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../db/server_database.dart';
import '../dtos/sync_request_dto.dart';
import '../dtos/sync_response_dto.dart';
import '../repositories/absence_repository.dart';
import '../repositories/plant_repository.dart';
import '../repositories/room_repository.dart';
import '../repositories/watering_event_repository.dart';

class SyncHandler {
  final ServerDatabase _db;
  final RoomRepository _rooms;
  final PlantRepository _plants;
  final WateringEventRepository _events;
  final AbsenceRepository _absences;

  SyncHandler(this._db)
      : _rooms = RoomRepository(_db),
        _plants = PlantRepository(_db),
        _events = WateringEventRepository(_db),
        _absences = AbsenceRepository(_db);

  Future<Response> call(Request request) async {
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } on FormatException {
      return Response(
        400,
        body: jsonEncode({'error': 'invalid_json'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final SyncRequestDto syncRequest;
    try {
      syncRequest = SyncRequestDto.fromJson(body);
    } on TypeError catch (e) {
      // Ein fehlendes oder falsch typisiertes Feld ist ein Client-Fehler, keine
      // Server-Störung. Ohne diesen Zweig verlässt der TypeError den Handler,
      // shelf macht daraus einen 500, und der Client übersetzt das zu "Server
      // nicht erreichbar" – er schickt denselben Datensatz dann bei jedem
      // weiteren Sync erneut und synchronisiert nie wieder.
      return Response(
        400,
        body: jsonEncode({'error': 'invalid_payload', 'detail': '$e'}),
        headers: {'content-type': 'application/json'},
      );
    }
    final receivedAt = DateTime.now().toUtc();

    // Schreiben UND Lesen laufen in DERSELBEN Transaktion: serverTime wird vor
    // den Schreibvorgängen bestimmt und vom Client als neues lastSyncedAt
    // gespeichert. Läge das Lesen außerhalb, könnte ein parallel committender
    // zweiter Client Datensätze mit einem received_at VOR dieser serverTime
    // schreiben, die diese Antwort nicht mehr enthält – sie fielen dauerhaft
    // aus dem Delta-Fenster des ersten Clients. Aktuell schützt bereits davor,
    // dass zwischen receivedAt und dem Antwortaufbau kein einziges `await`
    // steht (Dart unterbricht nur an Suspendierungspunkten); darauf soll sich
    // künftiger Code hier aber nicht verlassen müssen.
    final response = _db.transaction(() {
      for (final room in syncRequest.rooms) {
        _rooms.upsertIfNewer(room, receivedAt);
      }
      for (final plant in syncRequest.plants) {
        _plants.upsertIfNewer(plant, receivedAt);
      }
      for (final event in syncRequest.wateringEvents) {
        _events.insertIfAbsent(event, receivedAt);
      }
      for (final absence in syncRequest.absences) {
        _absences.upsertIfNewer(absence, receivedAt);
      }

      return SyncResponseDto(
        serverTime: receivedAt,
        rooms: _rooms.updatedSince(syncRequest.lastSyncedAt),
        plants: _plants.updatedSince(syncRequest.lastSyncedAt),
        wateringEvents: _events.receivedSince(syncRequest.lastSyncedAt),
        absences: _absences.updatedSince(syncRequest.lastSyncedAt),
      );
    });

    return Response.ok(
      jsonEncode(response.toJson()),
      headers: {'content-type': 'application/json'},
    );
  }
}
