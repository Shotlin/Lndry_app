import '../../models/models.dart';

/// Customer-facing wording for a laundry's rating and distance — real values
/// only. The screens used to invent them when the server had nothing (a rating
/// of 4.8, a review count and a distance derived from the vendor id's hash
/// code), which showed customers made-up social proof and made the "nearest"
/// sort meaningless.
extension VendorDisplay on VendorModel {
  /// True only when real customer reviews back the rating.
  bool get hasReviews => reviewCount > 0 && averageRating != null;

  /// "4.6" for a reviewed laundry, "New" for one with no reviews yet.
  String get ratingLabel => hasReviews ? averageRating!.toStringAsFixed(1) : 'New';

  /// "4.6 (23)" or "New".
  String get ratingWithCountLabel => hasReviews ? '$ratingLabel ($reviewCount)' : 'New';

  /// "2.4 km", or null when the server could not compute a distance.
  String? get distanceLabel =>
      distanceKm == null ? null : '${distanceKm!.toStringAsFixed(1)} km';

  /// Sort/filter key: unknown distances go last instead of being faked.
  double get distanceForSort => distanceKm ?? double.infinity;
}
