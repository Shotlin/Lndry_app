// Freezed constructor parameters are synthesized into real fields, but the
// analyzer doesn't know that — it flags @JsonKey on a constructor param as
// targeting the "wrong" element. This is the standard, package-recommended
// workaround for freezed + json_serializable field renaming.
// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'banner_model.freezed.dart';
part 'banner_model.g.dart';

/// Promotional banner shown on the Home screen carousel (and elsewhere).
/// Backend response shape (already Cloudinary-normalized image URLs):
/// `{ id, title, subtitle, image_url, banner_type, link_type, link_value,
///    sort_order, is_active, start_date, end_date, created_at, updated_at }`
@freezed
class BannerModel with _$BannerModel {
  const factory BannerModel({
    required String id,
    required String title,
    String? subtitle,
    @JsonKey(name: 'image_url') String? imageUrl,
    @JsonKey(name: 'banner_type') @Default('carousel') String bannerType,
    @JsonKey(name: 'link_type') @Default('none') String linkType,
    @JsonKey(name: 'link_value') String? linkValue,
    @JsonKey(name: 'sort_order') @Default(0) int sortOrder,
    @JsonKey(name: 'is_active') @Default(true) bool isActive,
    @JsonKey(name: 'start_date') DateTime? startDate,
    @JsonKey(name: 'end_date') DateTime? endDate,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
  }) = _BannerModel;

  factory BannerModel.fromJson(Map<String, dynamic> json) =>
      _$BannerModelFromJson(json);
}
