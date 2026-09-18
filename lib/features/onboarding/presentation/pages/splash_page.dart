import '../../../../core/constants/app_constants.dart';
import '../../../../core/design/design_system.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/widgets/app_skeleton.dart';
import '../../../../providers/auth_provider.dart';

class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _logoController;
  late Animation<double> _logoOpacity;

  // Guards against navigating before the animation finishes AND auth resolves.
  bool _minDelayDone = false;
  bool _navigationTriggered = false;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: AppCurves.standard),
    );
    _logoController.forward();

    // Minimum display time so the splash doesn't flash.
    Future.delayed(AppDurations.splash, () {
      if (!mounted) return;
      setState(() => _minDelayDone = true);
      _tryNavigate();
    });
  }

  @override
  void dispose() {
    _logoController.dispose();
    super.dispose();
  }

  /// Called both when the min-delay fires and when auth state updates.
  /// Only navigates once both conditions are satisfied.
  void _tryNavigate() {
    if (!mounted || _navigationTriggered) return;
    if (!_minDelayDone) return;

    final authState = ref.read(authProvider);

    // Still initialising — wait for the next state change (listener below).
    if (authState is AuthInitial || authState is AuthLoading) return;

    _navigationTriggered = true;

    final storage = ref.read(storageServiceProvider);
    final onboardingDone =
        storage.getBool(AppConstants.keyOnboardingDone) ?? false;

    if (!onboardingDone) {
      context.go(AppRoutes.onboarding);
      return;
    }

    // GoRouter redirect handles the exact destination based on auth state.
    // We only need to leave the splash route; the router picks the rest.
    switch (authState) {
      case AuthAuthenticated():
        context.go(AppRoutes.home);
      case AuthNeedsProfileSetup():
        context.go(AppRoutes.profileSetup);
      case AuthNeedsLocationPermission():
        context.go(AppRoutes.locationPermission);
      case AuthNeedsAddressSelection():
        context.go(AppRoutes.mapAddress);
      case AuthUnauthenticated():
        context.go(AppRoutes.home);
      default:
        context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen for auth state changes so we navigate as soon as both
    // the minimum delay AND auth resolution are done.
    ref.listen<AuthState>(authProvider, (_, next) {
      if (next is! AuthInitial && next is! AuthLoading) {
        _tryNavigate();
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFFFCFCFF),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _logoController,
          builder: (context, child) => Opacity(
            opacity: _logoOpacity.value,
            child: child,
          ),
          child: const _StartupSkeleton(),
        ),
      ),
    );
  }
}

class _StartupSkeleton extends StatelessWidget {
  const _StartupSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 600;
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: wide ? 64 : 24, vertical: 28),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  AppSkeleton.circle(size: 48),
                  SizedBox(width: 12),
                  AppSkeleton.line(width: 112, height: 22),
                ],
              ),
              SizedBox(height: 44),
              AppSkeleton.line(width: 220, height: 28),
              SizedBox(height: 12),
              AppSkeleton.line(width: 290, height: 16),
              SizedBox(height: 28),
              AppSkeleton.rectangular(height: 190, borderRadius: 28),
              SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: AppSkeleton.rectangular(height: 118, borderRadius: 20)),
                  SizedBox(width: 12),
                  Expanded(child: AppSkeleton.rectangular(height: 118, borderRadius: 20)),
                  SizedBox(width: 12),
                  Expanded(child: AppSkeleton.rectangular(height: 118, borderRadius: 20)),
                ],
              ),
              SizedBox(height: 28),
              AppSkeleton.rectangular(height: 66, borderRadius: 36),
              SizedBox(height: 14),
              AppSkeleton.rectangular(height: 66, borderRadius: 24),
            ],
          ),
        );
      },
    );
  }
}
