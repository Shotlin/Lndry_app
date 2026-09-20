import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../config/env.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../home/presentation/providers/home_providers.dart';
import 'address_serviceability_validator.dart';
import 'location_capture_service.dart';

/// The default address built from a GPS fix. `line1` is deliberately blank —
/// a reverse-geocoded street name is not the customer's real flat/house number,
/// and the checkout completeness guard asks for it before the first order.
AddressModel addressFromCaptured(CapturedLocation captured, {required String userId}) {
  return AddressModel(
    id: '',
    userId: userId,
    line1: '',
    line2: captured.formattedAddress.isNotEmpty ? captured.formattedAddress : null,
    city: captured.city,
    state: captured.state.isNotEmpty ? captured.state : captured.city,
    pincode: captured.pincode,
    landmark: null,
    type: AddressType.home,
    isDefault: true,
    coordinates: LatLng(latitude: captured.latitude, longitude: captured.longitude),
  );
}

/// Runs right after the customer allows location: fetch the current location
/// through the existing capture system and, for a signed-in customer with no
/// address yet, save it as the default so nearby laundries appear straight away.
///
/// Silent by design — if anything is missing (guest, GPS switched off, address
/// outside the service area, no network) it does nothing and the usual manual
/// address / location sheet remains available.
Future<void> autoDetectAddress(Ref ref) async {
  try {
    if (ref.read(authProvider) is! AuthAuthenticated) return;
    if (!await Geolocator.isLocationServiceEnabled()) return; // don't pop a second dialog

    final existing = await ref.read(currentAddressProvider.future);
    if (existing != null) return;

    final captured = await ref.read(locationCaptureServiceProvider).captureCurrentLocation();
    if (!Env.shouldBypassServiceability) {
      final error = await ref.read(addressServiceabilityValidatorProvider).validate(
            lat: captured.latitude,
            lng: captured.longitude,
            pincode: captured.pincode,
          );
      if (error != null) return;
    }

    final user = ref.read(currentUserProvider);
    await ref
        .read(authProvider.notifier)
        .completeAddressSelection(addressFromCaptured(captured, userId: user?.id ?? ''));
    ref
      ..invalidate(currentAddressProvider)
      ..invalidate(homeVendorsProvider)
      ..invalidate(homeCategoriesProvider);
  } catch (_) {
    // Falls back to manual selection.
  }
}
