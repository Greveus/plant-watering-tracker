import 'package:json_annotation/json_annotation.dart';

import 'plant_dto.dart';
import 'room_dto.dart';
import 'watering_event_dto.dart';

part 'sync_response_dto.g.dart';

@JsonSerializable()
class SyncResponseDto {
  final DateTime serverTime;
  final List<RoomDto> rooms;
  final List<PlantDto> plants;
  final List<WateringEventDto> wateringEvents;

  SyncResponseDto({
    required this.serverTime,
    required this.rooms,
    required this.plants,
    required this.wateringEvents,
  });

  factory SyncResponseDto.fromJson(Map<String, dynamic> json) =>
      _$SyncResponseDtoFromJson(json);
  Map<String, dynamic> toJson() => _$SyncResponseDtoToJson(this);
}
