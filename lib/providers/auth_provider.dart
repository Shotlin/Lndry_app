import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../config/env.dart';
import '../core/services/storage_service.dart';
import '../core/constants/app_constants.dart';
import '../core/network/network.dart';
import '../repositories/repositories.dart';

// ── Auth State ────────────────────────────────────────────────────────────────

sealed class AuthState {
  const AuthState();
}

/// App just launched; determining session state.
class AuthInitial extends AuthState {
  const AuthInitial();
}

/// Any async auth operation is in progress.
class AuthLoading extends AuthState {
  const AuthLoading();
}

/// OTP sent; waiting for user to enter code.
class AuthOtpSent extends AuthState {
  const AuthOtpSent({
    required this.phone,
    required this.challengeId,
    this.devOtp,
  });

  final String phone;

  /// Backend challenge ID for this OTP session.
  final String challengeId;

  /// Dev-only OTP value (populated in mock/dev mode; null in production).
  final String? devOtp;
}

/// OTP verified; new customer must complete profile.
class AuthNeedsProfileSetup extends AuthState {
  const AuthNeedsProfileSetup({required this.phone});
  final String phone;
}

/// Profile complete; needs location permission before address selection.
class AuthNeedsLocationPermission extends AuthState {
  const AuthNeedsLocationPermission({required this.user});
  final UserModel user;
}

/// Location granted; needs default address selection.
class AuthNeedsAddressSelection extends AuthState {
  const AuthNeedsAddressSelection({required this.user});
  final UserModel user;
}

/// Fully authenticated and onboarded.
class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.user);
  final UserModel user;
}

/// Not signed in; needs login.
class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

/// An auth operation failed; [message] is safe to display.
class AuthError extends AuthState {
  const AuthError(this.message);
  final String message;
}

// ── Auth Notifier ─────────────────────────────────────────────────────────────

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._repo, this._storage) : super(const AuthInitial()) {
    _init();
  }

  final CustomerRepository _repo;
  final StorageService _storage;

  // ── Initialisation (session restore via stored tokens) ──────────────────────

  Future<void> _init() async {
    state = const AuthLoading();

    // One-time session reset for fresh installs (clears stale dev data).
    final resetDone = _storage.getBool('fresh_install_reset_done_v3') ?? false;
    if (!resetDone) {
      await _storage.clearSession();
      await _clearUserPrefs();
      await _storage.saveBool('fresh_install_reset_done_v3', value: true);
    }

    // Try reading stored tokens from secure storage.
    final accessToken = await _storage.getSecure(AppConstants.keyAccessToken);
    final refreshToken = await _storage.getSecure(AppConstants.keyRefreshToken);

    if (accessToken == null && refreshToken == null) {
      // Demo mode: try restoring previous session from saved prefs.
      final savedName = _storage.getString('user_name');
      if (Env.demoMode && savedName != null && savedName.isNotEmpty) {
        final savedEmail = _storage.getString('user_email') ?? '';
        final savedPhone = _storage.getString('user_phone') ?? '';
        state = AuthAuthenticated(UserModel(
          id: 'usr_demo',
          name: savedName,
          phone: savedPhone,
          email: savedEmail.isNotEmpty ? savedEmail : null,
          role: UserRole.customer,
          isVerified: true,
        ));
        return;
      }
      state = const AuthUnauthenticated();
      return;
    }

    // Attempt to restore session by refreshing the token pair.
    try {
      final pair = await _repo.refreshTokens();

      // Store refreshed tokens
      await _storage.saveSecure(AppConstants.keyAccessToken, pair.accessToken);
      await _storage.saveSecure(
          AppConstants.keyRefreshToken, pair.refreshToken);

      // Fetch user profile
      final user = await _repo.getProfile();
      await _saveUserPrefs(user);
      await _registerDeviceIfPossible();

      // Handle server-side profile deletion edge case
      if (_needsProfileSetup(user)) {
        state = AuthNeedsProfileSetup(phone: user.phone);
        return;
      }

      _routeAfterAuth(user: user);
    } catch (_) {
      // Token refresh failed — clear everything and go to login.
      await _storage.clearSession();
      await _clearUserPrefs();
      state = const AuthUnauthenticated();
    }
  }

  // ── OTP flow ───────────────────────────────────────────────────────────────

  /// Requests an OTP for [phone] via the active repository.
  Future<void> sendOtp(String phone) async {
    state = const AuthLoading();
    try {
      final result = await _repo.sendOtp(phone);
      state = AuthOtpSent(
        phone: phone,
        challengeId: result.challengeId,
        devOtp: result.devOtp,
      );
    } catch (e) {
      state = AuthError(
        e is ApiException ? e.message : 'Failed to send OTP. Please try again.',
      );
    }
  }

  /// Verifies OTP [code] against the active challenge.
  Future<void> verifyOtp(String code) async {
    final prev = state;
    if (prev is! AuthOtpSent) return;

    state = const AuthLoading();
    try {
      final result = await _repo.verifyOtp(
        phone: prev.phone,
        otp: code,
        challengeId: prev.challengeId,
        device: await _buildDeviceInfo(),
      );

      // Persist tokens
      await _storage.saveSecure(
          AppConstants.keyAccessToken, result.accessToken);
      await _storage.saveSecure(
          AppConstants.keyRefreshToken, result.refreshToken);
      await _saveUserPrefs(result.user);
      await _registerDeviceIfPossible();

      if (result.isNewUser || _needsProfileSetup(result.user)) {
        state = AuthNeedsProfileSetup(phone: result.user.phone);
      } else {
        _routeAfterAuth(user: result.user);
      }
    } on ApiException catch (e) {
      state = AuthError(e.message);
    } catch (e) {
      state = AuthError('Verification failed. Please try again.');
    }
  }

  /// Restores [AuthOtpSent] for the previous phone after an error.
  void restoreOtpState(String phone, String challengeId, {String? devOtp}) {
    state = AuthOtpSent(phone: phone, challengeId: challengeId, devOtp: devOtp);
  }

  /// Clears a transient error back to unauthenticated.
  void clearError() {
    if (state is AuthError) {
      state = const AuthUnauthenticated();
    }
  }

  // ── Profile completion ─────────────────────────────────────────────────────

  /// Saves new customer profile and advances to location-permission.
  /// Returns the referral code's redemption outcome (null if [referralCode]
  /// was left blank) — an invalid/already-used code never blocks profile
  /// completion itself, so callers should show it as a soft notice, not an
  /// error that undoes navigation.
  Future<ReferralRedemptionResult?> completeProfile({
    required String name,
    required String email,
    String? referralCode,
  }) async {
    final prev = state;
    final String? phone;
    if (prev is AuthNeedsProfileSetup) {
      phone = prev.phone;
    } else {
      return null;
    }

    state = const AuthLoading();
    try {
      final cleanEmail = email.trim().isEmpty ? null : email.trim();
      final cleanReferralCode =
          (referralCode?.trim().isEmpty ?? true) ? null : referralCode!.trim();
      // Update profile on backend
      final result = await _repo.updateProfile(UpdateProfileRequest(
        name: name,
        email: cleanEmail,
        referralCode: cleanReferralCode,
      ));

      final user = UserModel(
        id: '',
        name: name,
        phone: phone ?? '',
        email: cleanEmail,
        role: UserRole.customer,
        isVerified: true,
      );

      // Fetch profile from backend to get the real user object
      UserModel persisted;
      try {
        persisted = await _repo.getProfile();
      } catch (_) {
        persisted = result.user.id.isNotEmpty ? result.user : user;
      }

      await _saveUserPrefs(persisted);
      state = AuthAuthenticated(persisted);
      return result.referralOutcome;
    } catch (e) {
      state = prev;
      rethrow;
    }
  }

  // ── Location / Address flow ────────────────────────────────────────────────

  Future<void> completeLocationSetup() async {
    final prev = state;
    if (prev is! AuthNeedsLocationPermission) return;
    state = AuthNeedsAddressSelection(user: prev.user);
  }

  Future<void> completeAddressSelection(AddressModel address) async {
    final prev = state;
    final UserModel user;
    if (prev is AuthNeedsAddressSelection) {
      user = prev.user;
    } else if (prev is AuthAuthenticated) {
      user = prev.user;
    } else {
      return;
    }

    state = const AuthLoading();
    try {
      final savedAddress = await _repo.addAddress(address);
      await _repo.setDefaultAddress(savedAddress.id);
      await _storage.saveBool('user_has_address', value: true);
      await _storage.saveString('user_default_address_id', savedAddress.id);
      state = AuthAuthenticated(user);
    } catch (e) {
      state = prev;
      rethrow;
    }
  }

  // ── Profile update (for authenticated users) ───────────────────────────────

  Future<void> updateAuthenticatedUser({
    required String name,
    required String email,
  }) async {
    final prev = state;
    if (prev is! AuthAuthenticated) return;

    // A blank optional email is "not provided" — sending "" fails the
    // backend's email-format validation (same handling as completeProfile).
    final cleanEmail = email.trim().isEmpty ? null : email.trim();

    // Deliberately no local-only fallback: if the server doesn't confirm the
    // save, this throws so the caller shows an error instead of a success
    // message for a name that was never persisted.
    final result = await _repo.updateProfile(
      UpdateProfileRequest(name: name.trim(), email: cleanEmail),
    );

    // Re-read the persisted record so the app shows exactly what the server
    // (and the admin dashboard) now hold.
    UserModel persisted;
    try {
      persisted = await _repo.getProfile();
    } catch (_) {
      persisted = result.user;
    }
    await _saveUserPrefs(persisted);
    state = AuthAuthenticated(persisted);
  }

  Future<void> updateAuthenticatedAvatar(String avatarUrl) async {
    final prev = state;
    if (prev is! AuthAuthenticated) return;

    final updated = prev.user.copyWith(avatarUrl: avatarUrl);
    await _saveUserPrefs(updated);
    state = AuthAuthenticated(updated);
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  Future<void> logout() async {
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    // Detach this device while the session is still valid, then drop the FCM
    // token so this phone stops receiving the signed-out user's notifications
    // (a fresh token is issued for whoever signs in next).
    final deviceId = _storage.getString('device_id');
    if (deviceId != null && deviceId.isNotEmpty) {
      String? token;
      try {
        token = await FirebaseMessaging.instance
            .getToken()
            .timeout(const Duration(seconds: 3));
      } catch (_) {}
      try {
        await _repo.unregisterDevice(deviceId, fcmToken: token);
      } catch (_) {}
      try {
        await FirebaseMessaging.instance
            .deleteToken()
            .timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    try {
      await _repo.logout();
    } catch (_) {
      // Best-effort server-side invalidation
    }
    await _storage.clearSession();
    await _clearUserPrefs();
    state = const AuthUnauthenticated();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _routeAfterAuth({required UserModel user}) {
    state = AuthAuthenticated(user);
  }

  bool _needsProfileSetup(UserModel user) =>
      user.name.isEmpty && user.email == null;

  Future<void> _saveUserPrefs(UserModel user) async {
    await Future.wait([
      _storage.saveString(AppConstants.keyUserId, user.id),
      _storage.saveString('user_name', user.name),
      _storage.saveString('user_email', user.email ?? ''),
      _storage.saveString('user_phone', user.phone),
    ]);
  }

  Future<void> _clearUserPrefs() async {
    await Future.wait([
      _storage.remove('user_name'),
      _storage.remove('user_email'),
      _storage.remove('user_phone'),
      _storage.remove('user_has_address'),
      _storage.remove('user_default_address_id'),
      _storage.remove(AppConstants.keyLocationRepromptShown),
    ]);
  }

  Future<String> _getOrCreateDeviceId() async {
    var deviceId = _storage.getString('device_id');
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await _storage.saveString('device_id', deviceId);
    }
    return deviceId;
  }

  String get _platformString =>
      Platform.isAndroid ? 'android' : Platform.isIOS ? 'ios' : 'android';

  /// Real hardware model — not a marketing name (no "iPhone 15 Pro"-style
  /// lookup table), but far more identifying than the OS string alone.
  /// Best-effort: returns null if `device_info_plus` can't read it (e.g.
  /// an unsupported platform), never blocks login.
  Future<String?> _getDeviceModel() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        return '${info.manufacturer} ${info.model}'.trim();
      }
      if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        return info.utsname.machine;
      }
    } catch (_) {
      // Best-effort only.
    }
    return null;
  }

  /// Sent with every OTP verification (unlike [_registerDeviceIfPossible]'s
  /// FCM token registration, which silently no-ops without a working
  /// Firebase config — see CLAUDE.md's "Known incomplete state") so the
  /// admin dashboard's customer-detail "last active device" has something
  /// to show even before push notifications are wired up for real.
  Future<Map<String, dynamic>> _buildDeviceInfo() async {
    final deviceId = await _getOrCreateDeviceId();
    final model = await _getDeviceModel();
    return {
      'device_id': deviceId,
      'platform': _platformString,
      if (model != null && model.isNotEmpty) 'device_model': model,
    };
  }

  Future<void> _registerDeviceIfPossible() async {
    try {
      final messaging = FirebaseMessaging.instance;
      // Never prompt from here — the permission prompter owns that. Without
      // permission there is nothing to deliver to, so wait until it is granted
      // (it calls syncPushToken right after the user allows).
      final settings = await messaging.getNotificationSettings();
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        return;
      }
      final token = await messaging.getToken();
      if (token == null || token.isEmpty) return;

      await _sendFcmToken(token);
      // Firebase rotates tokens; keep the backend's copy current.
      _tokenRefreshSub ??= messaging.onTokenRefresh.listen(_sendFcmToken);
    } catch (_) {
      // Firebase config is optional for local/dev builds; auth must continue.
    }
  }

  StreamSubscription<String>? _tokenRefreshSub;

  /// Register / refresh this device's FCM token with the backend now (called
  /// right after the user allows notifications). A signed-out user is
  /// registered at login instead.
  Future<void> syncPushToken() async {
    if (state is AuthUnauthenticated || state is AuthInitial) return;
    await _registerDeviceIfPossible();
  }

  Future<void> _sendFcmToken(String token) async {
    try {
      // Signed out: nothing to register (it is sent again at login).
      if (state is AuthUnauthenticated || state is AuthInitial) return;
      final deviceId = await _getOrCreateDeviceId();
      await _repo.registerDevice(
        deviceId: deviceId,
        platform: _platformString,
        fcmToken: token,
        deviceModel: await _getDeviceModel(),
      );
    } catch (_) {}
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final repo = ref.watch(customerRepositoryProvider);
  final storage = ref.watch(storageServiceProvider);
  return AuthNotifier(repo, storage);
});

/// Convenience provider: returns the current authenticated user, or null.
final currentUserProvider = Provider<UserModel?>((ref) {
  final s = ref.watch(authProvider);
  return switch (s) {
    AuthAuthenticated(:final user) => user,
    AuthNeedsLocationPermission(:final user) => user,
    AuthNeedsAddressSelection(:final user) => user,
    _ => null,
  };
});
