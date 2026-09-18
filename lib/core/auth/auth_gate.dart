import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gap/gap.dart';

import '../../providers/auth_provider.dart';
import '../../core/design/design_system.dart';
import '../router/app_routes.dart';

typedef PendingAuthAction = FutureOr<void> Function(
  BuildContext context,
  WidgetRef ref,
);

final pendingAuthActionProvider = StateProvider<PendingAuthAction?>((ref) {
  return null;
});

bool isAuthenticated(AuthState state) => state is AuthAuthenticated;

String currentRouteLocation(BuildContext context) {
  try {
    return GoRouterState.of(context).uri.toString();
  } catch (_) {
    return AppRoutes.home;
  }
}

String loginLocation({required String returnTo}) {
  return Uri(
    path: AppRoutes.login,
    queryParameters: returnTo.isEmpty ? null : {'returnTo': returnTo},
  ).toString();
}

String otpLocation({String? returnTo}) {
  return Uri(
    path: AppRoutes.otp,
    queryParameters:
        returnTo == null || returnTo.isEmpty ? null : {'returnTo': returnTo},
  ).toString();
}

String? returnToFrom(BuildContext context) {
  final value = GoRouterState.of(context).uri.queryParameters['returnTo'];
  return value == null || value.isEmpty ? null : value;
}

Future<void> requireAuthenticated({
  required BuildContext context,
  required WidgetRef ref,
  required PendingAuthAction action,
  String? returnTo,
}) async {
  final target = returnTo ?? currentRouteLocation(context);
  if (isAuthenticated(ref.read(authProvider))) {
    await action(context, ref);
    return;
  }

  // Present above the shell itself so the footer cannot paint over the sheet.
  final shouldProceed = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _LoginPromptSheet(),
  );

  if (shouldProceed != true) return;
  if (!context.mounted) return;

  final PendingAuthAction wrappedAction = (ctx, r) async {
    final navigator = rootNavigatorKey.currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.popUntil((route) =>
          route.settings.name != AppRouteNames.login &&
          route.settings.name != AppRouteNames.otp &&
          route.settings.name != AppRouteNames.profileSetup &&
          route.settings.name != AppRouteNames.locationPermission &&
          route.settings.name != AppRouteNames.mapAddress);
    }
    await action(ctx, r);
  };

  ref.read(pendingAuthActionProvider.notifier).state = wrappedAction;
  context.push(loginLocation(returnTo: target));
}

/// Premium, CRED-inspired sign-in bottom sheet displayed when a guest tries
/// a protected action. Frosted-glass sheet + 3D glossy hero visual + a
/// purple→aqua gradient CTA — the app's most-seen conversion moment, so it
/// gets the most polish.
class _LoginPromptSheet extends StatelessWidget {
  const _LoginPromptSheet();

  static const _benefits = [
    _Benefit(
      imagePath: 'assets/icons/lndry_bag.png',
      title: 'Book laundry services',
      helper: 'Schedule pickups in a few taps',
    ),
    _Benefit(
      imagePath: 'assets/icons/lndry_map.png',
      title: 'Save addresses',
      helper: 'Faster checkout, every time',
    ),
    _Benefit(
      imagePath: 'assets/icons/lndry_rider_icon.png',
      title: 'Track orders',
      helper: 'Real-time updates, always',
    ),
    _Benefit(
      imagePath: 'assets/icons/lndry_cupon.png',
      title: 'View invoices',
      helper: 'All your bills in one place',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final heroWidth = MediaQuery.sizeOf(context).width;
    final heroHeight = heroWidth * (887 / 1774);

    return ClipRRect(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(AppRadius.sheet.r)),
      child: BackdropFilter(
        // Frosts whatever's behind the sheet for the premium glass feel.
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            gradient: AppColors.signInSheetGradient,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(AppRadius.sheet.r)),
            border: Border.all(
                color: AppColors.white.withValues(alpha: 0.6), width: 1),
            boxShadow: AppElevation.high,
          ),
          child: Stack(
            children: [
              // Faint brand-tech grid overlay across the whole sheet.
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _GridPatternPainter()),
                ),
              ),
              SafeArea(
                top: false,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Hero visual ───────────────────────────────────
                      Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.topCenter,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.vertical(
                                top: Radius.circular(AppRadius.sheet.r)),
                            child: SizedBox(
                              width: double.infinity,
                              height: heroHeight,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.asset(
                                    'assets/images/img/Sign_in_poppop_bg.png',
                                    fit: BoxFit.cover,
                                    alignment: Alignment.center,
                                  ),
                                  // Bottom fade so the hero blends into the
                                  // sheet body instead of a hard cut line.
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.transparent,
                                          Colors.transparent,
                                          AppColors.lavenderTint
                                              .withValues(alpha: 0.9),
                                        ],
                                        stops: const [0.0, 0.72, 1.0],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Drag handle
                          Positioned(
                            top: AppSpacing.sm.h,
                            child: Container(
                              width: 40.w,
                              height: 4.h,
                              decoration: BoxDecoration(
                                color: AppColors.white.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(2.r),
                                boxShadow: const [
                                  BoxShadow(
                                      color: Color(0x1A000000), blurRadius: 4),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          AppSpacing.pagePaddingH.w,
                          0,
                          AppSpacing.pagePaddingH.w,
                          AppSpacing.pagePaddingV.h,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // ── Brand label ─────────────────────────────
                            ShaderMask(
                              shaderCallback: (bounds) => AppColors
                                  .signInCtaGradient
                                  .createShader(bounds),
                              child: Text(
                                'LNDRY',
                                textAlign: TextAlign.center,
                                style: AppTypography.overline.copyWith(
                                  color: AppColors.white,
                                  letterSpacing: 4,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Gap(AppSpacing.xs.h),

                            // ── Heading ──────────────────────────────────
                            Text(
                              'Sign in to continue',
                              textAlign: TextAlign.center,
                              style: AppTypography.headlineLarge.copyWith(
                                color: AppColors.lightTextPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Gap(AppSpacing.xs.h),

                            // ── Subheading ───────────────────────────────
                            RichText(
                              textAlign: TextAlign.center,
                              text: TextSpan(
                                style: AppTypography.bodyMedium.copyWith(
                                  color: AppColors.lightTextSecondary,
                                ),
                                children: const [
                                  TextSpan(text: 'Effortless laundry care, '),
                                  TextSpan(
                                    text: 'crafted for you.',
                                    style: TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Gap(AppSpacing.lg.h),

                            // ── Benefits card (2x2) ──────────────────────
                            Container(
                              padding: EdgeInsets.all(AppSpacing.sm.r),
                              decoration: BoxDecoration(
                                color: AppColors.white.withValues(alpha: 0.55),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.xl.r),
                                border: Border.all(
                                  color: AppColors.white.withValues(alpha: 0.8),
                                  width: 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                          child: _BenefitTile(_benefits[0])),
                                      Container(
                                          width: 1,
                                          height: 48.h,
                                          color: AppColors.outlineVariant),
                                      Expanded(
                                          child: _BenefitTile(_benefits[1])),
                                    ],
                                  ),
                                  Padding(
                                    padding: EdgeInsets.symmetric(
                                        vertical: AppSpacing.sm.h),
                                    child: Container(
                                        height: 1,
                                        color: AppColors.outlineVariant),
                                  ),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                          child: _BenefitTile(_benefits[2])),
                                      Container(
                                          width: 1,
                                          height: 48.h,
                                          color: AppColors.outlineVariant),
                                      Expanded(
                                          child: _BenefitTile(_benefits[3])),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Gap(AppSpacing.lg.h),

                            // ── CTA: Sign In ──────────────────────────────
                            _GlossyCtaButton(
                              label: 'Sign In',
                              onTap: () => Navigator.of(context).pop(true),
                            ),
                            Gap(AppSpacing.xs.h),

                            // ── Maybe later ───────────────────────────────
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              style: TextButton.styleFrom(
                                minimumSize: Size(double.infinity, 44.h),
                              ),
                              child: Text(
                                'Maybe later',
                                style: AppTypography.buttonText.copyWith(
                                  color: AppColors.lightTextSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Benefit {
  const _Benefit(
      {this.icon, this.imagePath, required this.title, required this.helper})
      : assert(icon != null || imagePath != null);
  final IconData? icon;

  /// Branded 3D icon asset (assets/icons/) — takes priority over [icon]
  /// when set, since these are illustrated glossy icons in their own right
  /// rather than glyphs needing a colored background chip.
  final String? imagePath;
  final String title;
  final String helper;
}

class _BenefitTile extends StatelessWidget {
  const _BenefitTile(this.benefit);
  final _Benefit benefit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(AppSpacing.sm.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          benefit.imagePath != null
              ? Image.asset(
                  benefit.imagePath!,
                  width: 34.r,
                  height: 34.r,
                  fit: BoxFit.contain,
                )
              : Container(
                  width: 34.r,
                  height: 34.r,
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    borderRadius: BorderRadius.circular(AppRadius.md.r),
                  ),
                  child:
                      Icon(benefit.icon, size: 18.r, color: AppColors.primary),
                ),
          Gap(AppSpacing.xs.h),
          Text(
            benefit.title,
            style: AppTypography.labelLarge.copyWith(
              color: AppColors.lightTextPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          Gap(2.h),
          Text(
            benefit.helper,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-width pill CTA with a purple→aqua gradient, a glossy top-highlight
/// sweep, and a soft outer glow — the "tappable and high-end" button asked
/// for in the design brief.
class _GlossyCtaButton extends StatelessWidget {
  const _GlossyCtaButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.button.r),
        child: Ink(
          height: 56.h,
          decoration: BoxDecoration(
            gradient: AppColors.signInCtaGradient,
            borderRadius: BorderRadius.circular(AppRadius.button.r),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: AppColors.aqua.withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Glossy top-highlight sweep for the acrylic feel.
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 24.h,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.vertical(
                        top: Radius.circular(AppRadius.button.r)),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.white.withValues(alpha: 0.35),
                        AppColors.white.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: AppTypography.buttonText.copyWith(
                        color: AppColors.white,
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Gap(AppSpacing.sm.w),
                    Container(
                      width: 26.r,
                      height: 26.r,
                      decoration: BoxDecoration(
                        color: AppColors.white.withValues(alpha: 0.22),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 16.r,
                        color: AppColors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Very faint tech-brand grid, drawn once behind the sheet content.
class _GridPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.03)
      ..strokeWidth = 1;
    const step = 28.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class PendingAuthActionRunner extends ConsumerStatefulWidget {
  const PendingAuthActionRunner({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<PendingAuthActionRunner> createState() =>
      _PendingAuthActionRunnerState();
}

class _PendingAuthActionRunnerState
    extends ConsumerState<PendingAuthActionRunner> {
  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next is! AuthAuthenticated) return;

      final action = ref.read(pendingAuthActionProvider);
      if (action == null) return;

      ref.read(pendingAuthActionProvider.notifier).state = null;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await action(context, ref);
      });
    });

    return widget.child;
  }
}
