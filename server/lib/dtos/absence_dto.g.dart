// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'absence_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AbsenceDto _$AbsenceDtoFromJson(Map<String, dynamic> json) => AbsenceDto(
  id: json['id'] as String,
  startDate: DateTime.parse(json['startDate'] as String),
  endDate: DateTime.parse(json['endDate'] as String),
  note: json['note'] as String?,
  updatedAt: DateTime.parse(json['updatedAt'] as String),
  deletedAt: json['deletedAt'] == null
      ? null
      : DateTime.parse(json['deletedAt'] as String),
);

Map<String, dynamic> _$AbsenceDtoToJson(AbsenceDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'startDate': instance.startDate.toIso8601String(),
      'endDate': instance.endDate.toIso8601String(),
      'note': instance.note,
      'updatedAt': instance.updatedAt.toIso8601String(),
      'deletedAt': instance.deletedAt?.toIso8601String(),
    };
