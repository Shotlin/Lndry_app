import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'storage_service.dart';

/// Captures a referral code carried through a Play Store install link, so a
/// friend who taps a shared "install LNDRY" link never has to type a code
/// by hand — the code rides along on the Play Store's own install-referrer
/// mechanism and is picked up automatically the first time the app opens.
///
/// Talks to a small native handler (`InstallReferrerBridge.kt`) wrapping
/// Google's official `com.android.installreferrer` library directly, rather
/// than the `android_play_install_referrer` pub package — that package's
/// bundled Android module hardcodes an old compileSdk and no longer builds
/// against this project's newer transitive androidx versions.
///
/// Share links built by [ReferEarnPage] use the referral code itself as the
/// Play Store `referrer` value (e.g. `...&referrer=7YH7K1I1`) — no extra
/// query-string parsing needed, since we control that format end to end.
/// This never touches the backend: it only pre-fills the same manual
/// "Referral Code" field on profile setup, which already knows how to
/// redeem a code. Manual entry keeps working exactly as before — this is
/// additive, not a replacement.
abstract final class ReferralAttributionService {
  static const _channel = MethodChannel('com.lndry.app/install_referrer');

  static const _checkedKey = 'referral_attribution_checked';
  static const _pendingCodeKey = 'pending_referral_code';

  /// Only ever meaningful once, right after a fresh install — the Play
  /// Install Referrer API has nothing new to say on later launches, so this
  /// is gated behind a one-time flag to avoid a wasted platform-channel
  /// call on every cold start.
  static Future<void> captureOnce(StorageService storage) async {
    if (storage.getString(_checkedKey) != null) return;
    await storage.saveString(_checkedKey, 'true');

    if (!Platform.isAndroid) return;

    try {
      final referrer = await _channel
          .invokeMethod<String>('getInstallReferrer')
          .timeout(const Duration(seconds: 4));
      final code = _extractCode(referrer);
      if (code != null) {
        await storage.saveString(_pendingCodeKey, code);
      }
    } catch (e) {
      // No Play Services (emulator, sideload, non-Play install source), a
      // timeout, or the API genuinely has nothing to say — silently skip.
      // Manual code entry is always still available.
      debugPrint('[LNDRY] Install referrer unavailable: $e');
    }
  }

  /// A simple alphanumeric code, same shape as the backend's generated
  /// referral codes — rejects anything that doesn't look like one (e.g. an
  /// empty referrer, or a raw UTM string from some other campaign link).
  static String? _extractCode(String? rawReferrer) {
    final value = rawReferrer?.trim().toUpperCase();
    if (value == null || value.isEmpty) return null;
    if (!RegExp(r'^[A-Z0-9]{4,20}$').hasMatch(value)) return null;
    return value;
  }

  /// Reads and clears the pending code in one shot — it is consumed at most
  /// once, whether the profile-setup screen auto-fills it successfully or
  /// not, so a later profile edit never silently re-applies an old code.
  static String? consumePendingCode(StorageService storage) {
    final code = storage.getString(_pendingCodeKey);
    if (code != null) storage.remove(_pendingCodeKey);
    return code;
  }
}
