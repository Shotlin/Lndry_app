import 'package:flutter_test/flutter_test.dart';
import 'package:lndry/core/extensions/extensions.dart';
import 'package:lndry/models/models.dart';

VendorModel _vendor({double? rating, int reviews = 0, double? distance}) => VendorModel(
      id: 'v1',
      name: 'Spotless Laundry',
      description: '',
      ownerName: 'Owner',
      phone: '9999999999',
      address: const AddressModel(
        id: 'a1', userId: 'u', line1: '1 Rd', city: 'Kolkata', state: 'WB', pincode: '700001', type: AddressType.home,
      ),
      averageRating: rating,
      reviewCount: reviews,
      distanceKm: distance,
    );

void main() {
  group('customers only ever see real ratings and distances', () {
    test('a laundry with no reviews is "New", never an invented 4.8', () {
      expect(_vendor(rating: 5.0, reviews: 0).ratingLabel, 'New');
      expect(_vendor(rating: null, reviews: 0).ratingLabel, 'New');
      expect(_vendor(rating: 5.0, reviews: 0).ratingWithCountLabel, 'New');
    });

    test('a reviewed laundry shows its real rating and review count', () {
      final v = _vendor(rating: 4.62, reviews: 23);
      expect(v.ratingLabel, '4.6');
      expect(v.ratingWithCountLabel, '4.6 (23)');
    });

    test('distance is shown only when the server computed it', () {
      expect(_vendor(distance: 4.5).distanceLabel, '4.5 km');
      expect(_vendor(distance: null).distanceLabel, isNull);
    });

    test('unknown distances sort last instead of being given a made-up value', () {
      final near = _vendor(distance: 0.4);
      final far = _vendor(distance: 9.0);
      final unknown = _vendor(distance: null);
      final sorted = [unknown, far, near]..sort((a, b) => a.distanceForSort.compareTo(b.distanceForSort));
      expect(sorted, [near, far, unknown]);
    });
  });
}
