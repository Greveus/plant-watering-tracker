import 'package:json_annotation/json_annotation.dart';

part 'plant_dto.g.dart';

@JsonSerializable()
class PlantDto {
  final String id;
  final String nickname;
  final String? presetId;
  final String? speciesFreeText;
  final String roomId;
  final String? photoPath;
  final DateTime createdAt;
  final String sizeCategory;
  final int? manualIntervalDays;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  PlantDto({
    required this.id,
    required this.nickname,
    this.presetId,
    this.speciesFreeText,
    required this.roomId,
    this.photoPath,
    required this.createdAt,
    required this.sizeCategory,
    this.manualIntervalDays,
    required this.updatedAt,
    this.deletedAt,
  });

  factory PlantDto.fromJson(Map<String, dynamic> json) => _$PlantDtoFromJson(json);
  Map<String, dynamic> toJson() => _$PlantDtoToJson(this);
}
