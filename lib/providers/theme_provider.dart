import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/app_constants.dart';
import '../core/services/storage_service.dart';

// ── Theme Mode Provider ───────────────────────────────────────────────────────

/// The app is light-mode only for now. While this is `false`:
///  * the Theme picker is hidden in Settings, and
///  * [ThemeModeNotifier] ignores any saved preference and refuses changes,
///    so the app always opens in light mode regardless of the phone's theme.
///
/// The dark theme (`AppTheme.darkTheme`), the persisted `keyThemeMode`
/// preference and the picker UI are all still in the codebase — flip this to
/// `true` to bring theme switching back.
const bool kThemeSwitchingEnabled = false;

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return ThemeModeNotifier(storage);
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(this._storage) : super(ThemeMode.light) {
    _load();
  }

  final StorageService _storage;

  void _load() {
    if (!kThemeSwitchingEnabled) {
      state = ThemeMode.light;
      return;
    }
    final saved = _storage.getString(AppConstants.keyThemeMode);
    state = switch (saved) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => ThemeMode.light,
    };
  }

  Future<void> setTheme(ThemeMode mode) async {
    if (!kThemeSwitchingEnabled) return;
    state = mode;
    await _storage.saveString(
      AppConstants.keyThemeMode,
      mode.name,
    );
  }

  Future<void> toggleTheme() async {
    final next =
        state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await setTheme(next);
  }
}
