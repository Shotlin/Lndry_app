import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_routes.dart';
import '../auth/auth_gate.dart';
import '../design/design_system.dart';
import '../widgets/milestone_perks_card.dart';
import '../../features/cart/presentation/providers/cart_providers.dart';
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
import '../../features/offers/presentation/pages/offers_page.dart';
import '../../features/wallet/presentation/pages/wallet_page.dart';
import '../../features/referrals/presentation/pages/refer_earn_page.dart';

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
    pageBuilder: (c, s) {
      final args = s.extra as MapAddressArgs?;
      return _slideTransition(
        context: c,
        state: s,
        child: MapAddressPage(
          existingAddress: args?.existingAddress,
          isEditingExisting: args?.isEditingExisting ?? false,
          requireFlatNumber: args?.requireFlatNumber ?? false,
          prefilledLocation: args?.prefilledLocation,
        ),
      );
    },
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
    pageBuilder: (c, s) => _slideTransition(
      context: c,
      state: s,
      child: CheckoutPage(
        assistedVendorId: s.uri.queryParameters['assistedVendor'],
      ),
    ),
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
        orderNumber: s.uri.queryParameters['orderNumber'],
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
            GoRoute(
              path: 'offers',
              name: AppRouteNames.offers,
              // Pinned to the root navigator: unlike its siblings here,
              // this route is also pushed from Checkout (`checkout_page.dart`
              // "View all"), which lives OUTSIDE this StatefulShellBranch.
              // Without this, reaching it via that cross-shell push made
              // go_router construct a second nested dashboard-shell instance
              // to satisfy the deep `/profile/offers` path, which rendered
              // blank (bottom nav visible, no page content) instead of the
              // Coupons & Offers screen. Pushing straight onto the root
              // navigator matches how every other full-page, no-bottom-nav
              // screen in this router (checkout, payment, vendor details...)
              // is already reached, and is unaffected for the existing
              // in-shell entry point (Profile page), since this is still a
              // plain full-screen push there either way.
              parentNavigatorKey: rootNavigatorKey,
              pageBuilder: (c, s) => _slideTransition(
                  context: c, state: s, child: const OffersPage()),
            ),
            GoRoute(
              path: 'wallet',
              name: AppRouteNames.wallet,
              pageBuilder: (c, s) => _slideTransition(
                  context: c, state: s, child: const WalletPage()),
            ),
            GoRoute(
              path: 'refer-earn',
              name: AppRouteNames.referEarn,
              pageBuilder: (c, s) => _slideTransition(
                  context: c, state: s, child: const ReferEarnPage()),
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
    final navHeight = 64.h;
    final navSide = 28.w;

    // The bottom nav has no Cart tab button (index 2 is reachable only via
    // "Continue" on a vendor page), so cartStateProvider's real server cart
    // was never fetched unless the customer had already opened Cart or just
    // added an item — leaving it at its empty default everywhere else,
    // including here. MilestonePerksCard needs the real cart to decide
    // whether to show at all, so kick off the (idempotent — see
    // CartNotifier.init) fetch as soon as the shell itself builds, not just
    // when a tab that happens to touch cart state is visited.
    ref.read(cartStateProvider.notifier).init();

    return PopScope(
      canPop: navigationShell.currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        navigationShell.goBranch(0);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            Positioned.fill(
              child: navigationShell,
            ),
            Positioned(
              left: navSide,
              right: navSide,
              bottom: 12.h,
              child: const MilestonePerksCard(),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          minimum: EdgeInsets.only(
            left: navSide,
            right: navSide,
            bottom: 8.h,
          ),
          child: SizedBox(
            height: navHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.white,
                borderRadius: BorderRadius.circular(AppRadius.full.r),
                border: Border.all(
                  color: isDark
                      ? AppColors.darkOutlineVariant
                      : AppColors.outlineVariant,
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.black.withValues(
                      alpha: isDark ? 0.45 : 0.10,
                    ),
                    blurRadius: 20,
                    spreadRadius: -4,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: AppColors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
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
                    ),
                    _NavItem(
                      shell: navigationShell,
                      index: 1,
                      unselected: Icons.grid_view_outlined,
                      selected: Icons.grid_view_rounded,
                    ),
                    _NavItem(
                      shell: navigationShell,
                      index: 3,
                      unselected: AppIcons.ordersOutlined,
                      selected: AppIcons.orders,
                    ),
                    _NavItem(
                      shell: navigationShell,
                      index: 4,
                      unselected: AppIcons.profileOutlined,
                      selected: AppIcons.profile,
                    ),
                  ],
                ),
              ),
            ),
          ),
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
  });

  final StatefulNavigationShell shell;
  final int index;
  final IconData unselected;
  final IconData selected;

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
        // No selected-state pill/circle behind the icon by design — only the
        // icon itself changes (outline → filled glyph, plus a color swap to
        // the brand highlight) so the bar stays flat and uncluttered.
        child: Center(
          child: AnimatedScale(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            scale: isSelected ? 1.1 : 1.0,
            child: Icon(
              isSelected ? selected : unselected,
              color: isSelected ? AppColors.primary : AppColors.black,
              size: isSelected ? 30.r : 27.r,
            ),
          ),
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
