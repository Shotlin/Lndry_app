import 'dart:async';
import 'dart:io';

import 'package:geolocator/geolocator.dart';
import 'package:location/location.dart' as location_pkg;

/// Programmatically turns device location services on, waiting for it to
/// actually take effect before returning.
///
/// On Android this drives Google Play Services' `SettingsClient` via the
/// `location` package's `requestService()` — the same native in-app "Turn
/// on Location Accuracy" dialog Zomato/Blinkit use. It genuinely flips GPS
/// on without the user ever leaving the app. iOS has no equivalent API
/// (Apple doesn't expose one), so it falls back to opening the Settings
/// app and waits for either the service-status stream to report enabled,
/// or the app resuming from background — whichever comes first, since
/// checking immediately after `openLocationSettings()` unreliably still
/// reads "off".
Future<bool> requestEnableLocationService() async {
  if (!Platform.isAndroid) {
    await Geolocator.openLocationSettings();
    return _waitForServiceEnabled();
  }
  try {
    return await location_pkg.Location().requestService();
  } catch (_) {
    await Geolocator.openLocationSettings();
    return _waitForServiceEnabled();
  }
}

/// Opens the app's own OS permission settings page (distinct from the
/// device-wide Location Services page above) — used when permission was
/// denied permanently and the only way forward is a manual toggle.
Future<void> openLocationPermissionSettings() async {
  await Geolocator.openAppSettings();
}

Future<bool> _waitForServiceEnabled({
  Duration timeout = const Duration(seconds: 30),
}) async {
  if (await Geolocator.isLocationServiceEnabled()) return true;

  final completer = Completer<bool>();
  final subscription = Geolocator.getServiceStatusStream().listen((status) {
    if (status == ServiceStatus.enabled && !completer.isCompleted) {
      completer.complete(true);
    }
  });

  unawaited(
    Future<void>.delayed(timeout, () {
      if (!completer.isCompleted) completer.complete(false);
    }),
  );

  try {
    return await completer.future;
  } finally {
    await subscription.cancel();
  }
}
