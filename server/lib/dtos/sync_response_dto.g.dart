// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_response_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SyncResponseDto _$SyncResponseDtoFromJson(Map<String, dynamic> json) =>
    SyncResponseDto(
      serverTime: DateTime.parse(json['serverTime'] as String),
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

Map<String, dynamic> _$SyncResponseDtoToJson(SyncResponseDto instance) =>
    <String, dynamic>{
      'serverTime': instance.serverTime.toIso8601String(),
      'rooms': instance.rooms,
      'plants': instance.plants,
      'wateringEvents': instance.wateringEvents,
    };
