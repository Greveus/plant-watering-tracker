// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'watering_event_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

WateringEventDto _$WateringEventDtoFromJson(Map<String, dynamic> json) =>
    WateringEventDto(
      id: json['id'] as String,
      plantId: json['plantId'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      feedbackTag: json['feedbackTag'] as String?,
      note: json['note'] as String?,
      receivedAt: json['receivedAt'] == null
          ? null
          : DateTime.parse(json['receivedAt'] as String),
    );

Map<String, dynamic> _$WateringEventDtoToJson(WateringEventDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'plantId': instance.plantId,
      'timestamp': instance.timestamp.toIso8601String(),
      'feedbackTag': instance.feedbackTag,
      'note': instance.note,
      'receivedAt': instance.receivedAt?.toIso8601String(),
    };
