import 'package:json_annotation/json_annotation.dart';

import 'absence_dto.dart';
import 'plant_dto.dart';
import 'room_dto.dart';
import 'watering_event_dto.dart';

part 'sync_request_dto.g.dart';

@JsonSerializable()
class SyncRequestDto {
  final String deviceId;
  final DateTime lastSyncedAt;
  final List<RoomDto> rooms;
  final List<PlantDto> plants;
  final List<WateringEventDto> wateringEvents;

  /// Ein Client, der den Urlaubsmodus noch nicht kennt, schickt dieses Feld
  /// nicht mit. Ohne den Default würde sein Sync am Server scheitern.
  @JsonKey(defaultValue: <AbsenceDto>[])
  final List<AbsenceDto> absences;

  SyncRequestDto({
    required this.deviceId,
    required this.lastSyncedAt,
    required this.rooms,
    required this.plants,
    required this.wateringEvents,
    this.absences = const [],
  });

  factory SyncRequestDto.fromJson(Map<String, dynamic> json) =>
      _$SyncRequestDtoFromJson(json);
  Map<String, dynamic> toJson() => _$SyncRequestDtoToJson(this);
}
