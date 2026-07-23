import 'package:json_annotation/json_annotation.dart';

part 'watering_event_dto.g.dart';

@JsonSerializable()
class WateringEventDto {
  final String id;
  final String plantId;
  final DateTime timestamp;
  final String? feedbackTag;
  final String? note;

  /// Server-Empfangszeitpunkt. Vom Client nie gesetzt (wird beim ersten
  /// Empfang durch den Server vergeben), aber in der Sync-Response enthalten
  /// — der Delta-Filter läuft über dieses Feld, nicht über [timestamp], damit
  /// rückwirkend erfasste Gieß-Events zuverlässig ankommen.
  final DateTime? receivedAt;

  WateringEventDto({
    required this.id,
    required this.plantId,
    required this.timestamp,
    this.feedbackTag,
    this.note,
    this.receivedAt,
  });

  factory WateringEventDto.fromJson(Map<String, dynamic> json) =>
      _$WateringEventDtoFromJson(json);
  Map<String, dynamic> toJson() => _$WateringEventDtoToJson(this);
}
