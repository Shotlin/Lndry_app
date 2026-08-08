import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/network.dart';

/// Validates a detected location against the backend's vendor-coverage and
/// pincode-availability checks before it's saved as a default address.
///
/// A standalone counterpart to `map_address_page.dart`'s private
/// `_validateBackendServiceability` (same two endpoints, same response
/// shape) — kept separate rather than shared, per the same "don't touch the
/// stable, untested map page" reasoning as [LocationCaptureService].
class AddressServiceabilityValidator {
  AddressServiceabilityValidator(this._dio);
  final Dio _dio;

  /// Returns a human-readable error message if the location/pincode isn't
  /// serviceable, or `null` if both checks pass.
  Future<String?> validate({
    required double lat,
    required double lng,
    required String pincode,
  }) async {
    try {
      final locationResponse = await _dio.post<dynamic>(
        ApiEndpoints.validateLocation,
        data: {'lat': lat, 'lng': lng},
      );
      final locationData = _dataMap(locationResponse);
      final serviceable = locationData['serviceable'] as bool? ?? false;
      final vendorCount =
          (locationData['eligible_vendor_count'] as num?)?.toInt() ?? 0;

      if (!serviceable || vendorCount == 0) {
        return 'No laundry partners currently serve this location. '
            'Try a nearby address or check back later.';
      }
    } on DioException {
      return 'Serviceability check failed. Please check your connection and try again.';
    }

    try {
      final pincodeResponse = await _dio.post<dynamic>(
        ApiEndpoints.validatePincode,
        data: {'pincode': pincode},
      );
      final pincodeData = _dataMap(pincodeResponse);
      final available = pincodeData['available'] as bool? ?? false;
      if (!available) {
        return 'Delivery is not yet available in pincode $pincode. '
            'We are expanding — please check back soon.';
      }
    } on DioException {
      return 'Pincode check failed. Please check your connection and try again.';
    }

    return null;
  }

  Map<String, dynamic> _dataMap(Response<dynamic> response) {
    final body = response.data;
    if (body is Map<String, dynamic>) {
      final data = body['data'];
      if (data is Map<String, dynamic>) return data;
      return body;
    }
    return const {};
  }
}

final addressServiceabilityValidatorProvider =
    Provider<AddressServiceabilityValidator>(
  (ref) => AddressServiceabilityValidator(ref.watch(dioClientProvider)),
);
