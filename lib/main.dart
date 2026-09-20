import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'config/config.dart';
import 'core/auth/auth_gate.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/tokens/breakpoints.dart';
import 'core/services/referral_attribution_service.dart';
import 'core/services/storage_service.dart';
import 'core/widgets/order_sync_listener.dart';
import 'providers/theme_provider.dart';
import 'core/network/friendly_error.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Portrait-only, regardless of the device's own rotation-lock setting —
  // matches the native Android/iOS orientation locks set on the platform
  // side (AndroidManifest.xml / Info.plist); this is a defensive third
  // layer in case a screen ever slips past those.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  final prefs = await SharedPreferences.getInstance();
  final storageService = StorageService(prefs: prefs);

  // One-time check (no-op on every launch after the first) for a referral
  // code carried through a Play Store install link, so a friend who taps a
  // shared link never has to type a code by hand at signup.
  await ReferralAttributionService.captureOnce(storageService);

  // Firebase initialisation is best-effort; the app runs without it in
  // offline/mock mode (FCM, auth still wired when backend is delivered).
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('[LNDRY] Firebase init skipped: ${friendlyError(e)}');
  }

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        storageServiceProvider.overrideWithValue(storageService),
      ],
      child: const LndryApp(),
    ),
  );
}

class LndryApp extends ConsumerWidget {
  const LndryApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);

    // Keep the static flag in sync with the resolved theme so
    // AppColors dynamic getters return the correct value.
    final systemIsDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    AppColors.isDarkMode = themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system && systemIsDark);

    return ScreenUtilInit(
      designSize: const Size(
        AppBreakpoints.designWidth,
        AppBreakpoints.designHeight,
      ),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp.router(
          key: ValueKey(themeMode),
          title: 'LNDRY',
          debugShowCheckedModeBanner: Env.showDebugBanner,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          routerConfig: router,
          builder: (context, child) {
            return OrderSyncListener(
              child: PendingAuthActionRunner(
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
        );
      },
    );
  }
}
