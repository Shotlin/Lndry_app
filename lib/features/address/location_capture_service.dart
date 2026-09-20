import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';

import '../../core/network/network.dart';
import '../../core/utils/location_service_resolver.dart';
import '../../core/utils/resilient_location.dart';
import '../../core/network/friendly_error.dart';

/// Base type for failures during [LocationCaptureService.captureCurrentLocation].
sealed class LocationCaptureException implements Exception {
  const LocationCaptureException(this.message);
  final String message;

  @override
  String toString() => message;
}

class LocationServiceOffException extends LocationCaptureException {
  const LocationServiceOffException()
      : super('Please enable location services to continue.');
}

class LocationPermissionDeniedException extends LocationCaptureException {
  const LocationPermissionDeniedException()
      : super('Location permission is required to detect your address.');
}

class LocationPermissionDeniedForeverException extends LocationCaptureException {
  const LocationPermissionDeniedForeverException()
      : super('Location permission is permanently denied. Please enable it '
            'from app settings.');
}

class ReverseGeocodeFailedException extends LocationCaptureException {
  const ReverseGeocodeFailedException()
      : super('Could not determine your address from this location.');
}

/// A GPS position resolved into a usable, human-readable address.
class CapturedLocation {
  const CapturedLocation({
    required this.latitude,
    required this.longitude,
    required this.line1,
    required this.formattedAddress,
    required this.city,
    required this.state,
    required this.pincode,
  });

  final double latitude;
  final double longitude;
  final String line1;
  final String formattedAddress;
  final String city;
  final String state;
  final String pincode;

  static final RegExp _pincodeRegExp = RegExp(r'^[1-9][0-9]{5}$');

  bool get isUsable => line1.isNotEmpty && _pincodeRegExp.hasMatch(pincode);
}

/// Detects the device's current GPS location and resolves it to a usable
/// address via reverse geocoding.
///
/// Mirrors the chain in `map_address_page.dart`'s
/// `_moveToCurrentLocation()`/`_reverseGeocode()` — same GPS-off auto-enable
/// dialog, same tiered position fetch, same Ola-Maps-first/OS-geocoder-
/// fallback reverse geocode — kept as a standalone implementation rather
/// than a shared extraction so that page's own logic is never touched by
/// this feature, but deliberately kept behaviorally identical: a user
/// hitting "enable location" from the home screen's sheet should see
/// exactly the same native turn-on flow as from the map picker, not a
/// dead-end error message.
class LocationCaptureService {
  const LocationCaptureService(this._dio);

  final Dio _dio;

  Future<CapturedLocation> captureCurrentLocation() async {
    var serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await requestEnableLocationService();
      if (!serviceEnabled) {
        throw const LocationServiceOffException();
      }
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationPermissionDeniedForeverException();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationPermissionDeniedException();
    }

    final position = await getResilientCurrentPosition();
    debugPrint('[LocationCapture] position lat=${position.latitude} '
        'lng=${position.longitude} accuracy=${position.accuracy}m '
        'age=${DateTime.now().difference(position.timestamp)}');

    final viaOla = await _reverseGeocodeViaOla(position);
    final captured = viaOla ?? await _reverseGeocodeViaOsGeocoder(position);
    debugPrint('[LocationCapture] resolved via=${viaOla != null ? 'ola' : 'os'} '
        'line1="${captured.line1}" city="${captured.city}" '
        'pincode="${captured.pincode}" isUsable=${captured.isUsable}');

    if (!captured.isUsable) {
      throw const ReverseGeocodeFailedException();
    }

    return captured;
  }

  Future<CapturedLocation?> _reverseGeocodeViaOla(Position position) async {
    try {
      final response = await _dio.get<dynamic>(
        '/maps/ola/reverse-geocode',
        queryParameters: {'lat': position.latitude, 'lng': position.longitude},
      );
      final body = response.data as Map<String, dynamic>? ?? {};
      final data = body['data'] as Map<String, dynamic>?;
      if (data == null || data.isEmpty) return null;

      final city = (data['city'] as String?)?.trim() ?? '';
      final formattedAddress = (data['formatted_address'] as String?)?.trim() ?? '';
      if (city.isEmpty && formattedAddress.isEmpty) return null;

      // `landmark` is only present for an actual named point of interest —
      // an ordinary residential/street address (the common case) has none,
      // which used to leave line1 empty and fail isUsable even though Ola
      // had genuinely resolved a perfectly good address. Fall back to the
      // locality, then to the most specific segment of the formatted
      // address, before giving up.
      final line1 = _firstNonEmpty([
        data['landmark'] as String?,
        data['locality'] as String?,
        formattedAddress.split(',').first,
      ]);

      return CapturedLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        line1: line1,
        formattedAddress: formattedAddress,
        city: city,
        state: (data['state'] as String?)?.trim() ?? city,
        pincode: (data['postal_code'] as String?)?.trim() ?? '',
      );
    } catch (e) {
      debugPrint('[LocationCapture] Ola Maps reverse-geocode failed, falling back: ${friendlyError(e)}');
      return null;
    }
  }

  Future<CapturedLocation> _reverseGeocodeViaOsGeocoder(Position position) async {
    List<geocoding.Placemark> places;
    try {
      places = await geocoding.placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
    } catch (e) {
      debugPrint('[LocationCapture] OS geocoder threw: ${friendlyError(e)}');
      throw const ReverseGeocodeFailedException();
    }
    if (places.isEmpty) {
      debugPrint('[LocationCapture] OS geocoder returned no placemarks');
      throw const ReverseGeocodeFailedException();
    }

    final place = places.first;

    final city = _firstNonEmpty([
      place.locality,
      place.subAdministrativeArea,
      place.administrativeArea,
      place.subLocality,
    ]);
    final state = _firstNonEmpty([
      place.administrativeArea,
      place.subAdministrativeArea,
      place.country,
    ]);
    final line1 = _firstNonEmpty([
      place.name,
      place.street,
      place.subLocality,
    ]);
    final formattedAddress = [
      place.name,
      place.street,
      place.subLocality,
      place.locality,
      place.administrativeArea,
    ].where((part) => part != null && part.trim().isNotEmpty).join(', ');
    final pincode = place.postalCode?.trim() ?? '';

    return CapturedLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      line1: line1,
      formattedAddress: formattedAddress,
      city: city,
      state: state,
      pincode: pincode,
    );
  }

  /// Whether the device currently has location services on AND permission
  /// granted. Routed through this service (instead of calling [Geolocator]
  /// directly from UI code) so callers remain unit-testable via provider
  /// overrides.
  Future<bool> isDeviceLocationEnabled() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  static String _firstNonEmpty(List<String?> candidates) {
    for (final c in candidates) {
      if (c != null && c.trim().isNotEmpty) return c.trim();
    }
    return '';
  }
}

final locationCaptureServiceProvider = Provider<LocationCaptureService>(
  (ref) => LocationCaptureService(ref.read(dioClientProvider)),
);
