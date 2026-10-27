import 'dart:io';
import 'flavors.dart';

/// LNDRY Environment Configuration
/// Resolves the correct API base URL and feature flags per flavor.
/// All keys are injected via --dart-define; never hard-code credentials.
abstract final class Env {
  Env._();

  static final AppFlavor _flavor = AppFlavor.current;

  // ── API Base URL (injected via --dart-define=API_BASE_URL=...) ────────────
  /// Resolves in priority order:
  ///   1. --dart-define=API_BASE_URL  (developer/CI supplied)
  ///   2. Platform-appropriate emulator localhost
  ///   3. Flavor-based fallback URL
  static const String _dartDefineBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static String get baseUrl {
    if (_dartDefineBaseUrl.isNotEmpty) return _dartDefineBaseUrl;
    return switch (_flavor) {
      AppFlavor.development =>
        // Android emulator → host machine; update for physical device / iOS
        'http://10.0.2.2:4500/api/v1',
      AppFlavor.staging => 'https://api-staging.lndry.app/v1',
      AppFlavor.production => 'https://api.lndry.in/api/v1',
    };
  }

  // ── Socket.IO base URL ─────────────────────────────────────────────────────
  /// Socket.IO connects to the server root, not the REST prefix — same
  /// derivation as Lndry_vendor_app's `Env.socketBaseUrl`.
  static String get socketBaseUrl {
    const suffix = '/api/v1';
    return baseUrl.endsWith(suffix)
        ? baseUrl.substring(0, baseUrl.length - suffix.length)
        : baseUrl;
  }

  // ── Mock flag ─────────────────────────────────────────────────────────────
  /// When true, every repository resolves to the MockCustomerRepository.
  /// Only set this for visual/golden tests or offline UI review.
  /// Normal local development should talk to the real local backend.
  static const bool _useMocksFlag = bool.fromEnvironment(
    'USE_MOCKS',
    defaultValue: false,
  );
  static bool get useMocksForVisualTestsOnly => _flavor.isDev && _useMocksFlag;

  // ── Demo Mode Toggle ──────────────────────────────────────────────────────
  /// Set this to true to enable local client-only Demo Mode.
  /// When true, the app will run entirely locally using mock repositories,
  /// When false, the app reverts to normal production behavior.
  static const bool demoMode = false;

  // ── Auto-Fill OTP for Testing ─────────────────────────────────────────────
  /// When true, the OTP verification screen automatically populates with 123456
  /// and auto-submits the form. OFF unless a developer opts in with
  /// `--dart-define=AUTOFILL_TEST_OTP=true` — it used to be hard-coded on, so every
  /// debug/profile build quietly behaved unlike the shipped app.
  static const bool autoFillOtpForTesting =
      bool.fromEnvironment('AUTOFILL_TEST_OTP', defaultValue: false);
  static bool get shouldAutoFillOtp =>
      !isReleaseBuild &&
      !Platform.environment.containsKey('FLUTTER_TEST') &&
      (demoMode || autoFillOtpForTesting);

  // ── Bypass Serviceability for Testing ────────────────────────────────────
  /// When true, the address selection flow skips the backend serviceability
  /// check and allows any location to be saved.
  /// OFF by default so debug/profile builds enforce the same serviceability
  /// rules as the release app (previously any non-release build skipped the
  /// check, so an address could be saved that no laundry serves and Home then
  /// showed nothing). Opt in only for UI work:
  /// `--dart-define=BYPASS_SERVICEABILITY=true`. Never honoured in release.
  static const bool bypassServiceabilityForTesting =
      bool.fromEnvironment('BYPASS_SERVICEABILITY', defaultValue: false);
  static bool get shouldBypassServiceability =>
      !isReleaseBuild && (demoMode || bypassServiceabilityForTesting);


  // Build mode flags.
  static const bool isReleaseBuild = bool.fromEnvironment('dart.vm.product');
  static const bool isProfileBuild = bool.fromEnvironment('dart.vm.profile');
  static const bool isDebugBuild = !isReleaseBuild && !isProfileBuild;

  // ── Debug banner ──────────────────────────────────────────────────────────
  static bool get showDebugBanner => _flavor.isDev && isDebugBuild;

  /// Network logging is intentionally metadata-only and debug-build-only.
  static bool get enableNetworkLogging => _flavor.isDev && isDebugBuild;

  // ── Feature Flags ─────────────────────────────────────────────────────────
  static bool get enableCrashlytics => _flavor.isProduction;
  static bool get enableAnalytics => !_flavor.isDev;

  // ── Keys (injected via --dart-define) ─────────────────────────────────────
  static const String googleMapsKey = String.fromEnvironment(
    'GOOGLE_MAPS_KEY',
    defaultValue: '',
  );

  static const String razorpayKey = String.fromEnvironment(
    'RAZORPAY_KEY',
    defaultValue: '',
  );

  // ── Timeouts ──────────────────────────────────────────────────────────────
  static const int connectTimeoutMs = 30000;
  static const int receiveTimeoutMs = 30000;

  // ── App Info ──────────────────────────────────────────────────────────────
  static AppFlavor get flavor => _flavor;
  static String get flavorLabel => _flavor.label;

  // ── Play Store ────────────────────────────────────────────────────────────
  /// Matches `applicationId` in android/app/build.gradle.kts. A referral
  /// share link appends `&referrer=<code>` — Play Store carries that value
  /// through install so the app can read it back via the Play Install
  /// Referrer API on first launch (see ReferralAttributionService).
  static const String androidPackageName = 'com.lndry.app';
  static String get playStoreUrl =>
      'https://play.google.com/store/apps/details?id=$androidPackageName';
}
