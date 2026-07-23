// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'plant_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PlantDto _$PlantDtoFromJson(Map<String, dynamic> json) => PlantDto(
  id: json['id'] as String,
  nickname: json['nickname'] as String,
  presetId: json['presetId'] as String?,
  speciesFreeText: json['speciesFreeText'] as String?,
  roomId: json['roomId'] as String,
  photoPath: json['photoPath'] as String?,
  createdAt: DateTime.parse(json['createdAt'] as String),
  sizeCategory: json['sizeCategory'] as String,
  manualIntervalDays: (json['manualIntervalDays'] as num?)?.toInt(),
  updatedAt: DateTime.parse(json['updatedAt'] as String),
  deletedAt: json['deletedAt'] == null
      ? null
      : DateTime.parse(json['deletedAt'] as String),
);

Map<String, dynamic> _$PlantDtoToJson(PlantDto instance) => <String, dynamic>{
  'id': instance.id,
  'nickname': instance.nickname,
  'presetId': instance.presetId,
  'speciesFreeText': instance.speciesFreeText,
  'roomId': instance.roomId,
  'photoPath': instance.photoPath,
  'createdAt': instance.createdAt.toIso8601String(),
  'sizeCategory': instance.sizeCategory,
  'manualIntervalDays': instance.manualIntervalDays,
  'updatedAt': instance.updatedAt.toIso8601String(),
  'deletedAt': instance.deletedAt?.toIso8601String(),
};
