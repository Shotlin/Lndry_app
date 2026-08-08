import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_routes.dart';
import '../auth/auth_gate.dart';
import '../design/design_system.dart';
import '../widgets/milestone_perks_card.dart';
import '../../providers/auth_provider.dart';

// ── Page imports ──────────────────────────────────────────────────────────────

import '../../features/onboarding/presentation/pages/onboarding_page.dart';
import '../../features/onboarding/presentation/pages/splash_page.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/otp_page.dart';
import '../../features/auth/presentation/pages/profile_setup_page.dart';
import '../../features/auth/presentation/pages/location_permission_page.dart';
import '../../features/auth/presentation/pages/map_address_page.dart';

import '../../features/home/presentation/pages/home_page.dart';
import '../../features/search/presentation/pages/search_page.dart';
import '../../features/category/presentation/pages/category_page.dart';
import '../../features/vendor_listing/presentation/pages/vendor_listing_page.dart';
import '../../features/vendor_details/presentation/pages/vendor_details_page.dart';

import '../../features/cart/presentation/pages/cart_page.dart';
import '../../features/checkout/presentation/pages/checkout_page.dart';
import '../../features/checkout/presentation/pages/payment_page.dart';
import '../../features/orders/presentation/pages/order_confirmation_page.dart';

import '../../features/orders/presentation/pages/orders_list_page.dart';
import '../../features/orders/presentation/pages/order_details_page.dart';

import '../../features/profile/presentation/pages/profile_page.dart';
import '../../features/profile/presentation/pages/edit_profile_page.dart';
import '../../features/profile/presentation/pages/saved_addresses_page.dart';
import '../../features/profile/presentation/pages/notifications_page.dart';
import '../../features/profile/presentation/pages/my_reviews_page.dart';
import '../../features/profile/presentation/pages/last_order_review_page.dart';
import '../../features/profile/presentation/pages/settings_page.dart';
import '../../features/profile/presentation/pages/help_page.dart';

// ── Custom Transitions ────────────────────────────────────────────────────────

CustomTransitionPage<T> _slideTransition<T>({
  required BuildContext context,
  required GoRouterState state,
  required Widget child,
}) =>
    CustomTransitionPage<T>(
      key: state.pageKey,
      child: child,
      transitionDuration: AppDurations.pageRoute,
      reverseTransitionDuration: AppDurations.pageRoute,
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1.0, 0.0),
          end: Offset.zero,
        ).animate(
            CurvedAnimation(parent: animation, curve: AppCurves.decelerate)),
        child: child,
      ),
    );

CustomTransitionPage<T> _fadeTransition<T>({
  required BuildContext context,
  required GoRouterState state,
  required Widget child,
}) =>
    CustomTransitionPage<T>(
      key: state.pageKey,
      child: child,
      transitionDuration: AppDurations.pageRoute,
      reverseTransitionDuration: AppDurations.pageRoute,
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: AppCurves.standard),
        child: child,
      ),
    );

// ── Router Provider ───────────────────────────────────────────────────────────

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshListenable = ValueNotifier<int>(0);
  ref
    ..onDispose(refreshListenable.dispose)
    ..listen<AuthState>(authProvider, (_, __) {
      refreshListenable.value++;
    });

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,
    refreshListenable: refreshListenable,
    redirect: (context, state) =>
        _globalRedirect(context, state, ref.read(authProvider)),
    errorBuilder: (context, state) => _ErrorPage(error: state.error),
    routes: _routes,
  );
});

// ── Global redirect (auth guard) ──────────────────────────────────────────────

String? _globalRedirect(
  BuildContext context,
  GoRouterState state,
  AuthState authState,
) {
  final path = state.uri.path;
  final returnTo = state.uri.queryParameters['returnTo'];

  const protectedPaths = [
    AppRoutes.profile,
    AppRoutes.search,
    AppRoutes.profileSetup,
    AppRoutes.locationPermission,
    AppRoutes.mapAddress,
    AppRoutes.cart,
    AppRoutes.checkout,
    AppRoutes.payment,
    AppRoutes.orders,
    AppRoutes.editProfile,
    AppRoutes.address,
    AppRoutes.notifications,
    AppRoutes.myReviews,
  ];

  final isProtectedPath = protectedPaths.contains(path) ||
      path.startsWith('/orders/details/') ||
      (path.startsWith('/orders/') && path.endsWith('/submitted'));

  // While initialising or loading, stay put (don't flicker).
  if (authState is AuthInitial || authState is AuthLoading) return null;

  // Check if we are already on an auth or onboarding page.
  // NOTE: AppRoutes.mapAddress is intentionally excluded — unlike the other
  // paths here, it's a legitimate destination for already-authenticated
  // users too (adding/changing an address from Home or Saved Addresses),
  // not just a one-time onboarding step. The AuthNeedsLocationPermission/
  // AuthNeedsAddressSelection branches below each have their own explicit
  // path check, so they don't depend on it being listed here.
  final isAuthOrOnboardingPath = path == AppRoutes.login ||
      path == AppRoutes.otp ||
      path == AppRoutes.profileSetup ||
      path == AppRoutes.locationPermission;

  // Auth error: allow public browsing and send protected routes to login.
  if (authState is AuthError) {
    if (isProtectedPath) return loginLocation(returnTo: state.uri.toString());
    return null;
  }

  if (authState is AuthUnauthenticated) {
    if (isProtectedPath) return loginLocation(returnTo: state.uri.toString());
    return null;
  }

  if (authState is AuthOtpSent) {
    if (isAuthOrOnboardingPath) return null;
    if (path != AppRoutes.otp) return otpLocation(returnTo: returnTo);
    return null;
  }

  if (authState is AuthNeedsProfileSetup) {
    if (isAuthOrOnboardingPath) return null;
    if (path != AppRoutes.profileSetup) return AppRoutes.profileSetup;
    return null;
  }

  if (authState is AuthNeedsLocationPermission) {
    if (isAuthOrOnboardingPath) return null;
    if (path != AppRoutes.locationPermission) {
      return AppRoutes.locationPermission;
    }
    return null;
  }

  if (authState is AuthNeedsAddressSelection) {
    if (isAuthOrOnboardingPath) return null;
    if (path != AppRoutes.mapAddress) return AppRoutes.mapAddress;
    return null;
  }

  if (authState is AuthAuthenticated) {
    // ROOT CAUSE FIX: Only redirect from auth/onboarding pages.
    // Do NOT redirect from public pages like /search or /home.
    if (isAuthOrOnboardingPath) {
      return _safeReturnTo(returnTo) ?? AppRoutes.home;
    }
    return null;
  }

  return null;
}

String? _safeReturnTo(String? returnTo) {
  if (returnTo == null || returnTo.isEmpty) return null;
  final uri = Uri.tryParse(returnTo);
  if (uri == null || uri.hasScheme || uri.host.isNotEmpty) return null;
  if (uri.path == AppRoutes.login || uri.path == AppRoutes.otp) return null;
  return returnTo;
}

// ── Route definitions ─────────────────────────────────────────────────────────

final List<RouteBase> _routes = [
  // ── Splash / Onboarding ───────────────────────────────────────────────────
  GoRoute(
    path: AppRoutes.splash,
    name: AppRouteNames.splash,
    pageBuilder: (c, s) =>
        _fadeTransition(context: c, state: s, child: const SplashPage()),
  ),
  GoRoute(
    path: AppRoutes.onboarding,
    name: AppRouteNames.onboarding,
    pageBuilder: (c, s) =>
        _fadeTransition(context: c, state: s, child: const OnboardingPage()),
  ),

  // ── Auth ──────────────────────────────────────────────────────────────────
  GoRoute(
    path: AppRoutes.login,
    name: AppRouteNames.login,
    pageBuilder: (c, s) =>
        _slideTransition(context: c, state: s, child: const LoginPage()),
  ),
  GoRoute(
    path: AppRoutes.otp,
    name: AppRouteNames.otp,
    pageBuilder: (c, s) =>
        _slideTransition(context: c, state: s, child: const OtpPage()),
  ),
  GoRoute(
    path: AppRoutes.profileSetup,
    name: AppRouteNames.profileSetup,
    pageBuilder: (c, s) =>
        _slideTransition(context: c, state: s, child: const ProfileSetupPage()),
  ),
  GoRoute(
    path: AppRoutes.locationPermission,
    name: AppRouteNames.locationPermission,
    pageBuilder: (c, s) => _slideTransition(
        context: c, state: s, child: const LocationPermissionPage()),
  ),
  GoRoute(
    path: AppRoutes.mapAddress,
    name: AppRouteNames.mapAddress,
    pageBuilder: (c, s) =>
        _slideTransition(context: c, state: s, child: const MapAddressPage()),
  ),

  // ── Vendor discovery (outside shell so no bottom nav shown) ───────────────
  GoRoute(
    path: '/category/:categoryId',
    name: AppRouteNames.category,
    pageBuilder: (c, s) => _slideTransition(
      context: c,
      state: s,
      child: CategoryPage(categoryId: s.pathParameters['categoryId']!),
    ),
  ),
  GoRoute(
    path: '/vendors',
    name: AppRouteNames.vendorListing,
    pageBuilder: (c, s) => _slideTransition(
        context: c, state: s, child: const VendorListingPage()),
  ),
  GoRoute(
    path: '/vendor/:vendorId',
    name: AppRouteNames.vendorDetails,
    pageBuilder: (c, s) => _slideTransition(
      context: c,
      state: s,
      child: VendorDetailsPage(vendorId: s.pathParameters['vendorId']!),
    ),
  ),

  // ── Booking / Checkout (outside shell) ───────────────────────────────────
  GoRoute(
    path: AppRoutes.checkout,
    name: AppRouteNames.checkout,
    pageBuilder: (c, s) =>
        _slideTransition(context: c, state: s, child: const CheckoutPage()),
  ),
  GoRoute(
    path: AppRoutes.payment,
    name: AppRouteNames.payment,
    pageBuilder: (c, s) =>
        _slideTransition(context: c, state: s, child: const PaymentPage()),
  ),

  // ── Order confirmation (/orders/:orderId/submitted) ───────────────────────
  GoRoute(
    path: '/orders/:orderId/submitted',
    name: AppRouteNames.orderConfirmation,
    pageBuilder: (c, s) => _fadeTransition(
      context: c,
      state: s,
      child: OrderConfirmationPage(
        orderId: s.pathParameters['orderId']!,
      ),
    ),
  ),

  // ── Dashboard tabs (StatefulShellRoute) ──────────────────────────────────
  StatefulShellRoute.indexedStack(
    builder: (_, __, shell) => _DashboardShell(navigationShell: shell),
    branches: [
      // Tab 0: Home
      StatefulShellBranch(routes: [
        GoRoute(
          path: AppRoutes.home,
          name: AppRouteNames.home,
          builder: (c, s) => const HomePage(),
          routes: [
            GoRoute(
              path: 'last-order-review',
              name: AppRouteNames.lastOrderReview,
              pageBuilder: (c, s) => _slideTransition(
                  context: c, state: s, child: const LastOrderReviewPage()),
            ),
          ],
        ),
      ]),

      // Tab 1: Search/Explore
      StatefulShellBranch(routes: [
        GoRoute(
          path: AppRoutes.search,
          name: AppRouteNames.search,
          builder: (c, s) => const SearchPage(),
        ),
      ]),

      // Tab 2: Cart/Booking
      StatefulShellBranch(routes: [
        GoRoute(
          path: AppRoutes.cart,
          name: AppRouteNames.cart,
          builder: (c, s) => const CartPage(),
        ),
      ]),

      // Tab 3: Orders
      StatefulShellBranch(routes: [
        GoRoute(
          path: AppRoutes.orders,
          name: AppRouteNames.orders,
          builder: (c, s) => const OrdersListPage(),
          routes: [
            GoRoute(
              path: 'details/:orderId',
              name: AppRouteNames.orderDetails,
              pageBuilder: (c, s) => _slideTransition(
                context: c,
                state: s,
                child: OrderDetailsPage(orderId: s.pathParameters['orderId']!),
              ),
            ),
          ],
        ),
      ]),

      // Tab 4: Profile
      StatefulShellBranch(routes: [
        GoRoute(
          path: AppRoutes.profile,
          name: AppRouteNames.profile,
          builder: (c, s) => const ProfilePage(),
          routes: [
            GoRoute(
              path: 'edit',
              name: AppRouteNames.editProfile,
              pageBuilder: (c, s) => _slideTransition(
                  context: c, state: s, child: const EditProfilePage()),
            ),
            GoRoute(
              path: 'address',
              name: AppRouteNames.address,
              pageBuilder: (c, s) => _slideTransition(
                  context: c, state: s, child: const SavedAddressesPage()),
            ),
            GoRoute(
              path: 'notifications',
              name: AppRouteNames.notifications,
              pageBuilder: (c, s) => _slideTransition(
                  context: c, state: s, child: const NotificationsPage()),
            ),
            GoRoute(
              path: 'reviews',
              name: AppRouteNames.myReviews,
              pageBuilder: (c, s) => _slideTransition(
                  context: c, state: s, child: const MyReviewsPage()),
            ),
            GoRoute(
              path: 'settings',
              name: AppRouteNames.settings,
              pageBuilder: (c, s) => _slideTransition(
                  context: c, state: s, child: const SettingsPage()),
            ),
            GoRoute(
              path: 'help',
              name: AppRouteNames.help,
              pageBuilder: (c, s) => _slideTransition(
                  context: c, state: s, child: const HelpPage()),
            ),
          ],
        ),
      ]),
    ],
  ),
];

// ── Dashboard Shell ───────────────────────────────────────────────────────────

class _DashboardShell extends ConsumerWidget {
  const _DashboardShell({required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final navHeight = 64.h;
    final navSide = 28.w;
    final navBottom = 8.h + safeBottom;

    return PopScope(
      canPop: navigationShell.currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        navigationShell.goBranch(0);
      },
      child: Scaffold(
        // Safety-net fallback only — tab content is now full-bleed (see
        // below), so this rarely paints. Kept non-transparent because a
        // fully transparent Scaffold here renders as a black void on
        // Android whenever anything (overscroll bounce, page transition)
        // exposes it, which is worse than the flat-white "box" this used
        // to show behind the pill.
        backgroundColor: AppColors.background,
        body: Stack(
          clipBehavior: Clip.none,
          children: [
            // Tab content fills the whole screen edge-to-edge — no reserved
            // clearance band of any kind behind the pill. Reserving extra
            // bottom inset here (as a previous version of this did) always
            // paints as a solid Scaffold-background rectangle wherever real
            // content doesn't reach — invisible when that color was white,
            // impossible to miss once the app background became a solid
            // color. The pill only ever floats over genuine, live content
            // now (softened by its own BackdropFilter blur below), never
            // over a dead reserved strip.
            Positioned.fill(
              child: navigationShell,
            ),
            // Milestone perks card — floats directly above the nav pill,
            // real box on purpose (unlike the pill, this is meant to read
            // as a distinct card). Renders nothing when there's no cart or
            // no eligible offer, so it never reserves space it isn't using.
            Positioned(
              left: navSide,
              right: navSide,
              bottom: navBottom + navHeight + 12.h,
              child: const MilestonePerksCard(),
            ),
            // Fully custom floating pill — deliberately not Scaffold's
            // bottomNavigationBar / Material's NavigationBar or
            // BottomNavigationBar. Nothing behind it but real, live tab
            // content: whatever card/section happens to scroll underneath
            // is frosted via BackdropFilter instead of being left as a
            // hard-edged shape poking out from behind the pill, so no
            // matter what's back there it always reads as "glass", never
            // as a stray box.
            Positioned(
              left: navSide,
              right: navSide,
              bottom: navBottom,
              child: SizedBox(
                height: navHeight,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.full.r),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient:
                            isDark ? null : AppColors.signInSheetGradient,
                        color: isDark
                            ? AppColors.darkSurface.withValues(alpha: 0.7)
                            : AppColors.white.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(AppRadius.full.r),
                        border: Border.all(
                          color: AppColors.white
                              .withValues(alpha: isDark ? 0.14 : 0.85),
                          width: 1,
                        ),
                        boxShadow: [
                          // Soft, wide, low-opacity ambient shadow — reads
                          // as "hovering" rather than a hard drop shadow.
                          BoxShadow(
                            color:
                                (isDark ? AppColors.black : AppColors.primary)
                                    .withValues(alpha: isDark ? 0.35 : 0.16),
                            blurRadius: 24,
                            spreadRadius: -4,
                            offset: const Offset(0, 10),
                          ),
                          BoxShadow(
                            color: AppColors.black.withValues(alpha: 0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4.w),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                        _NavItem(
                          shell: navigationShell,
                          index: 0,
                          unselected: AppIcons.homeOutlined,
                          selected: AppIcons.home,
                          label: 'Home',
                        ),
                        _NavItem(
                          shell: navigationShell,
                          index: 1,
                          unselected: Icons.grid_view_outlined,
                          selected: Icons.grid_view_rounded,
                          label: 'Explore',
                        ),
                        _NavItem(
                          shell: navigationShell,
                          index: 3,
                          unselected: AppIcons.ordersOutlined,
                          selected: AppIcons.orders,
                          label: 'Orders',
                        ),
                        _NavItem(
                          shell: navigationShell,
                          index: 4,
                          unselected: AppIcons.profileOutlined,
                          selected: AppIcons.profile,
                          label: 'Profile',
                        ),
                      ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends ConsumerWidget {
  const _NavItem({
    required this.shell,
    required this.index,
    required this.unselected,
    required this.selected,
    required this.label,
  });

  final StatefulNavigationShell shell;
  final int index;
  final IconData unselected;
  final IconData selected;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSelected = shell.currentIndex == index;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          void goToBranch() {
            final navigator = rootNavigatorKey.currentState;
            if (navigator != null && navigator.canPop()) {
              navigator.popUntil((route) =>
                  route.settings.name != AppRouteNames.login &&
                  route.settings.name != AppRouteNames.otp &&
                  route.settings.name != AppRouteNames.profileSetup &&
                  route.settings.name != AppRouteNames.locationPermission &&
                  route.settings.name != AppRouteNames.mapAddress);
            }
            shell.goBranch(
              index,
              initialLocation: index == shell.currentIndex,
            );
          }

          // Home (0) stays open to guests for browsing; Explore, Orders and
          // Profile all need a real account, so gate them the same way with
          // the friendly sign-in prompt instead of a silent router redirect.
          const protectedIndexes = {1, 3, 4};
          if (protectedIndexes.contains(index)) {
            final returnTo = switch (index) {
              1 => AppRoutes.search,
              3 => AppRoutes.orders,
              4 => AppRoutes.profile,
              _ => AppRoutes.home,
            };
            requireAuthenticated(
              context: context,
              ref: ref,
              returnTo: returnTo,
              action: (_, __) => goToBranch(),
            );
            return;
          }
          goToBranch();
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.all(isSelected ? 6.r : 0),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primaryContainer
                    : AppColors.transparent,
                shape: BoxShape.circle,
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.28),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: AnimatedScale(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                scale: isSelected ? 1.08 : 1.0,
                child: Icon(
                  isSelected ? selected : unselected,
                  color:
                      isSelected ? AppColors.primary : AppColors.textSecondary,
                  size: 21.r,
                ),
              ),
            ),
            const Gap(4),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 250),
                  style: AppTypography.caption.copyWith(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                  child: Text(
                    label,
                    maxLines: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Error Page ────────────────────────────────────────────────────────────────

class _ErrorPage extends StatelessWidget {
  const _ErrorPage({this.error});
  final Exception? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(AppIcons.error, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text('Page not found', style: AppTypography.headlineSmall),
            const SizedBox(height: 8),
            Text(
              error?.toString() ?? 'Unknown route',
              style: AppTypography.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go(AppRoutes.home),
              child: const Text('Go Home'),
            ),
          ],
        ),
      ),
    );
  }
}
