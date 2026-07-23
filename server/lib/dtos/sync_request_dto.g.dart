// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_request_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SyncRequestDto _$SyncRequestDtoFromJson(Map<String, dynamic> json) =>
    SyncRequestDto(
      deviceId: json['deviceId'] as String,
      lastSyncedAt: DateTime.parse(json['lastSyncedAt'] as String),
      rooms: (json['rooms'] as List<dynamic>)
          .map((e) => RoomDto.fromJson(e as Map<String, dynamic>))
          .toList(),
      plants: (json['plants'] as List<dynamic>)
          .map((e) => PlantDto.fromJson(e as Map<String, dynamic>))
          .toList(),
      wateringEvents: (json['wateringEvents'] as List<dynamic>)
          .map((e) => WateringEventDto.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$SyncRequestDtoToJson(SyncRequestDto instance) =>
    <String, dynamic>{
      'deviceId': instance.deviceId,
      'lastSyncedAt': instance.lastSyncedAt.toIso8601String(),
      'rooms': instance.rooms,
      'plants': instance.plants,
      'wateringEvents': instance.wateringEvents,
    };
