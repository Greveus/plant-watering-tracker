import 'package:json_annotation/json_annotation.dart';

part 'absence_dto.g.dart';

/// Abwesenheitszeitraum ("Urlaubsmodus"). Gilt global für den gesamten
/// Pflanzenbestand und hängt deshalb an keiner plant_id.
@JsonSerializable()
class AbsenceDto {
  final String id;
  final DateTime startDate;
  final DateTime endDate;
  final String? note;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  AbsenceDto({
    required this.id,
    required this.startDate,
    required this.endDate,
    this.note,
    required this.updatedAt,
    this.deletedAt,
  });

  factory AbsenceDto.fromJson(Map<String, dynamic> json) => _$AbsenceDtoFromJson(json);
  Map<String, dynamic> toJson() => _$AbsenceDtoToJson(this);
}
