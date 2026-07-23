import 'package:json_annotation/json_annotation.dart';

part 'room_dto.g.dart';

@JsonSerializable()
class RoomDto {
  final String id;
  final String name;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  RoomDto({
    required this.id,
    required this.name,
    required this.updatedAt,
    this.deletedAt,
  });

  factory RoomDto.fromJson(Map<String, dynamic> json) => _$RoomDtoFromJson(json);
  Map<String, dynamic> toJson() => _$RoomDtoToJson(this);
}
