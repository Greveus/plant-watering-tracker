import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../db/server_database.dart';
import '../dtos/sync_request_dto.dart';
import '../dtos/sync_response_dto.dart';
import '../repositories/plant_repository.dart';
import '../repositories/room_repository.dart';
import '../repositories/watering_event_repository.dart';

class SyncHandler {
  final ServerDatabase _db;
  final RoomRepository _rooms;
  final PlantRepository _plants;
  final WateringEventRepository _events;

  SyncHandler(this._db)
      : _rooms = RoomRepository(_db),
        _plants = PlantRepository(_db),
        _events = WateringEventRepository(_db);

  Future<Response> call(Request request) async {
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } on FormatException {
      return Response(400, body: jsonEncode({'error': 'invalid_json'}));
    }

    final syncRequest = SyncRequestDto.fromJson(body);
    final receivedAt = DateTime.now().toUtc();

    _db.transaction(() {
      for (final room in syncRequest.rooms) {
        _rooms.upsertIfNewer(room, receivedAt);
      }
      for (final plant in syncRequest.plants) {
        _plants.upsertIfNewer(plant, receivedAt);
      }
      for (final event in syncRequest.wateringEvents) {
        _events.insertIfAbsent(event, receivedAt);
      }
      return null;
    });

    final response = SyncResponseDto(
      serverTime: receivedAt,
      rooms: _rooms.updatedSince(syncRequest.lastSyncedAt),
      plants: _plants.updatedSince(syncRequest.lastSyncedAt),
      wateringEvents: _events.receivedSince(syncRequest.lastSyncedAt),
    );

    return Response.ok(
      jsonEncode(response.toJson()),
      headers: {'content-type': 'application/json'},
    );
  }
}
