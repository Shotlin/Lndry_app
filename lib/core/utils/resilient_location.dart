import 'package:geolocator/geolocator.dart';

/// A cached fix this old, or this imprecise, is more likely to reverse-
/// geocode into nothing (or the wrong place entirely) than to save the
/// user any real time — not worth trusting blindly.
const _maxTrustedCacheAge = Duration(minutes: 3);
const _maxTrustedCacheAccuracyMeters = 200;

/// Fetches the current GPS position with tiered fallback.
///
/// A single unguarded `getCurrentPosition()` called right after the user
/// re-enables location (from the settings prompt) regularly hangs or
/// fails outright, because the OS's location subsystem hasn't "warmed up"
/// yet. This tries, in order: the last cached fix — but only when it's
/// recent and accurate enough to trust (a stale or low-accuracy cached
/// fix reverse-geocodes into "could not determine your address" far more
/// often than a fresh one, which is exactly the failure this was letting
/// through silently) — then a fast low-accuracy attempt, then a slower
/// medium-accuracy attempt, falling back to the cached fix one more time
/// before finally giving up.
Future<Position> getResilientCurrentPosition() async {
  final cached = await Geolocator.getLastKnownPosition();
  if (cached != null &&
      DateTime.now().difference(cached.timestamp) <= _maxTrustedCacheAge &&
      cached.accuracy <= _maxTrustedCacheAccuracyMeters) {
    return cached;
  }

  try {
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.low,
      timeLimit: const Duration(seconds: 12),
    );
  } catch (_) {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 20),
      );
    } catch (err, stack) {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) return lastKnown;
      Error.throwWithStackTrace(err, stack);
    }
  }
}
