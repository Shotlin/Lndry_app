import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/auth/auth_gate.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/design/design_system.dart';
import '../../../../core/extensions/extensions.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../models/models.dart';
import '../../../../providers/providers.dart';
import '../../../../shared/widgets/domain_cards.dart';
import '../../../../shared/widgets/premium_3d_icon.dart';
import '../../../../shared/widgets/shared_widgets.dart';
import '../../../../repositories/repositories.dart';
import '../../../address/location_capture_service.dart';
import '../../../cart/presentation/providers/cart_providers.dart';
import '../../../offers/presentation/providers/offers_providers.dart';
import '../providers/home_providers.dart';
import '../widgets/location_capture_sheet.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  // Issue 2: No category selected initially
  int _selectedCategoryIdx = -1;

  bool _locationPromptEvaluated = false;
  bool _isScanningForVendors = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _maybeShowLocationPrompt());
  }

  /// Shows the location-capture sheet when appropriate:
  /// - the user has no saved default address (every cold start until resolved), or
  /// - they have one but device location is currently off (once per off-cycle).
  Future<void> _maybeShowLocationPrompt() async {
    if (!mounted || _locationPromptEvaluated) return;
    if (ref.read(authProvider) is! AuthAuthenticated) return;

    _locationPromptEvaluated = true;

    AddressModel? address;
    try {
      address = await ref.read(currentAddressProvider.future);
    } catch (_) {
      return;
    }
    if (!mounted) return;

    if (address == null) {
      final wantsManualEntry = await showLocationCaptureSheet(context);
      if (wantsManualEntry && mounted) context.push(AppRoutes.mapAddress);
      return;
    }

    bool locationOn;
    try {
      locationOn = await ref
          .read(locationCaptureServiceProvider)
          .isDeviceLocationEnabled();
    } catch (_) {
      return;
    }
    if (!mounted) return;

    final storage = ref.read(storageServiceProvider);
    if (locationOn) {
      if (storage.getBool(AppConstants.keyLocationRepromptShown) ?? false) {
        await storage.saveBool(AppConstants.keyLocationRepromptShown,
            value: false);
      }
      return;
    }

    if (storage.getBool(AppConstants.keyLocationRepromptShown) ?? false) return;
    await storage.saveBool(AppConstants.keyLocationRepromptShown, value: true);
    if (!mounted) return;

    final wantsManualEntry =
        await showLocationCaptureSheet(context, isReprompt: true);
    if (wantsManualEntry && mounted) context.push(AppRoutes.mapAddress);
  }

  /// -1 means nothing in the 4-step mini tracker is reached yet — used for
  /// every pre-pickup status so a not-yet-picked-up order doesn't show
  /// "Picked up" as already complete.
  int _activeOrderStep(OrderStatus status) {
    return switch (status) {
      OrderStatus.waitingForVendorConfirmation ||
      OrderStatus.vendorAccepted ||
      OrderStatus.pickupAssigned ||
      OrderStatus.goingForPickup =>
        -1,
      OrderStatus.pickupOtpVerified ||
      OrderStatus.pickedUp ||
      OrderStatus.receivedAtVendor =>
        0,
      OrderStatus.processing => 1,
      OrderStatus.packed => 2,
      OrderStatus.deliveryAssigned ||
      OrderStatus.outForDelivery ||
      OrderStatus.deliveryOtpVerified ||
      OrderStatus.delivered =>
        3,
      _ => -1,
    };
  }

  String _activeOrderSubtitle(OrderStatus status) {
    return switch (status) {
      OrderStatus.waitingForVendorConfirmation =>
        'Waiting for the vendor to confirm your order',
      OrderStatus.vendorAccepted ||
      OrderStatus.pickupAssigned =>
        'Pickup is being scheduled',
      OrderStatus.goingForPickup => 'Pickup partner is on the way',
      OrderStatus.pickupOtpVerified ||
      OrderStatus.pickedUp =>
        'Your clothes have been picked up',
      OrderStatus.receivedAtVendor => 'Arrived at the laundry partner',
      OrderStatus.processing => 'Your clothes are being cleaned',
      OrderStatus.packed => 'Packed and ready for delivery',
      OrderStatus.deliveryAssigned ||
      OrderStatus.outForDelivery =>
        'Out for delivery',
      OrderStatus.deliveryOtpVerified || OrderStatus.delivered => 'Delivered',
      _ => 'Order in progress',
    };
  }

  @override
  Widget build(BuildContext context) {
    final addressAsync = ref.watch(currentAddressProvider);
    final categoriesAsync = ref.watch(homeCategoriesProvider);
    final vendorsAsync = ref.watch(homeVendorsProvider);
    final activeOrdersAsync = ref.watch(activeOrdersProvider);
    final isAuthenticated = ref.watch(authProvider) is AuthAuthenticated;
    final hasNoAddress = addressAsync.hasValue && addressAsync.value == null;

    // Re-arm the location prompt check if a guest logs in while Home is
    // already mounted (Home is kept alive across bottom-nav tab switches,
    // so initState alone won't see a later login).
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next is AuthAuthenticated && previous is! AuthAuthenticated) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _maybeShowLocationPrompt());
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        // The hero image bleeds under the status bar (matches the reference
        // design) — its own content adds MediaQuery's top inset manually
        // instead of relying on SafeArea for it.
        top: false,
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            ref.invalidate(currentAddressProvider);
            ref.invalidate(homeCategoriesProvider);
            ref.invalidate(homeVendorsProvider);
            ref.invalidate(activeOrdersProvider);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 1+2+3. Hero image (Header + Greeting) with a floating
                // search bar straddling the boundary into the white content
                // below, fading/blurring into it for a premium transition
                // instead of a hard image-to-white cut.
                _HomeHeroSection(addressAsync: addressAsync),
                const Gap(16),

                // ── 4. Offer Banner Carousel (Issue 1) ────────────────────────
                const _OfferBannerCarousel(),
                const Gap(16),

                // ── 5. Category Scroll Row (Issue 2) ──────────────────────────
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20.w),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'What do you need?',
                          style: AppTypography.titleLarge.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textBlack,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      GestureDetector(
                        onTap: () =>
                            StatefulNavigationShell.of(context).goBranch(1),
                        child: Text(
                          'View all',
                          style: AppTypography.labelMedium.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Gap(12),
                SizedBox(
                  height: math.max(
                    132.h,
                    MediaQuery.textScalerOf(context).scale(132.h),
                  ),
                  child: categoriesAsync.when(
                    data: (cats) => ListView.separated(
                      padding: EdgeInsets.symmetric(
                        horizontal: 20.w,
                        vertical: 8.h,
                      ),
                      clipBehavior: Clip.none,
                      scrollDirection: Axis.horizontal,
                      itemCount: cats.length,
                      separatorBuilder: (_, __) => const Gap(12),
                      itemBuilder: (context, idx) {
                        final cat = cats[idx];
                        final isSelected = _selectedCategoryIdx == idx;
                        return AnimatedScale(
                          scale: isSelected ? 1.05 : 1.0,
                          duration: const Duration(milliseconds: 200),
                          child: CategoryCard(
                            category: cat,
                            isSelected: isSelected,
                            onTap: () {
                              setState(() {
                                // Toggle off if same category tapped
                                if (_selectedCategoryIdx == idx) {
                                  _selectedCategoryIdx = -1;
                                } else {
                                  _selectedCategoryIdx = idx;
                                  context.push('/category/${cat.id}');
                                }
                              });
                            },
                          ),
                        );
                      },
                    ),
                    loading: () => ListView.separated(
                      padding: EdgeInsets.symmetric(
                        horizontal: 20.w,
                        vertical: 8.h,
                      ),
                      clipBehavior: Clip.none,
                      scrollDirection: Axis.horizontal,
                      itemCount: 5,
                      separatorBuilder: (_, __) => const Gap(12),
                      itemBuilder: (_, __) =>
                          const AppSkeletonCard(width: 90, height: 110),
                    ),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ),
                const Gap(16),

                // ── 6. Quick Schedule Card (Issue 5) ─────────────────────────
                const _QuickScheduleCard(),
                const Gap(24),

                // ── 7. Active Order Status Tracker ────────────────────────────
                activeOrdersAsync.when(
                  data: (orders) {
                    if (orders.isEmpty) return const SizedBox.shrink();
                    final order = orders.first;
                    return Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20.w),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  'Active order',
                                  style: AppTypography.titleLarge.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textBlack,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              GestureDetector(
                                onTap: () =>
                                    context.push('/orders/details/${order.id}'),
                                child: Text(
                                  'Track',
                                  style: AppTypography.labelMedium.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Gap(12),
                          _ActiveOrderTrackerCard(
                            order: order,
                            currentStep: _activeOrderStep(order.status),
                            statusText: _activeOrderSubtitle(order.status),
                          ),
                          const Gap(24),
                        ],
                      ),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),

                // ── 8. Guest / logged-in conditional section ──────────────────
                // Guest: premium benefits section instead of a confusing
                // "no laundry partners nearby" empty state before they've
                // even signed in or shared a location.
                // Authenticated + no address: compact permission card, not
                // a full empty-state screen.
                // Authenticated + address: real nearby recommendations.
                if (!isAuthenticated)
                  _GuestBenefitsSection(
                    onSignIn: () => requireAuthenticated(
                      context: context,
                      ref: ref,
                      action: (context, _) {
                        ref.invalidate(currentAddressProvider);
                        ref.invalidate(homeVendorsProvider);
                      },
                    ),
                    onContinueAsGuest: () =>
                        StatefulNavigationShell.of(context).goBranch(1),
                  )
                else if (hasNoAddress)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20.w),
                    child: _LocationPermissionCompactCard(
                      onTap: () async {
                        final wantsManualEntry =
                            await showLocationCaptureSheet(context);
                        if (wantsManualEntry && context.mounted) {
                          context.push(AppRoutes.mapAddress);
                        }
                      },
                    ),
                  )
                else
                  _buildRecommendedNearYou(vendorsAsync, addressAsync),
                const Gap(24),

                // ── 9. "Special offers" Section (Issue 4) ─────────────────────
                const _SpecialOffersSection(),
                const Gap(32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Authenticated-with-address path: the real "Recommended near you"
  /// header + vendor list/empty/loading/error states, unchanged from
  /// before — only reached once we know the user is signed in and has a
  /// resolved address (see the conditional branch in [build]).
  Widget _buildRecommendedNearYou(
    AsyncValue<List<VendorModel>> vendorsAsync,
    AsyncValue<AddressModel?> addressAsync,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.w),
          child: Text(
            'Recommended near you',
            style: AppTypography.titleLarge.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textBlack,
            ),
          ),
        ),
        const Gap(12),
        vendorsAsync.when(
          data: (vendors) {
            if (vendors.isEmpty) {
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: _buildEmptyVendorState(
                  hasAddress: addressAsync.value != null,
                ),
              );
            }
            return SizedBox(
              height: 180.h,
              child: ListView.separated(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                scrollDirection: Axis.horizontal,
                itemCount: vendors.length,
                separatorBuilder: (_, __) => const Gap(16),
                itemBuilder: (context, idx) {
                  final vendor = vendors[idx];
                  return SizedBox(
                    width: 315.w,
                    child: _HorizontalVendorCard(
                      vendor: vendor,
                      onTap: () => context.push('/vendor/${vendor.id}'),
                    ),
                  );
                },
              ),
            );
          },
          loading: () => SizedBox(
            height: 180.h,
            child: ListView.separated(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              scrollDirection: Axis.horizontal,
              itemCount: 2,
              separatorBuilder: (_, __) => const Gap(16),
              itemBuilder: (_, __) =>
                  const AppSkeletonCard(width: 315, height: 180),
            ),
          ),
          error: (_, __) => Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: AppEmptyState(
              icon: AppIcons.store,
              title: 'Couldn\'t load nearby partners',
              subtitle: 'Check your connection and try again.',
              actionLabel: 'Retry',
              onAction: () => ref.invalidate(homeVendorsProvider),
            ),
          ),
        ),
      ],
    );
  }

  /// Issue 3: Empty vendor state.
  ///
  /// [hasAddress] distinguishes two very different situations that used to
  /// share the same "Enable Location" copy/action:
  ///  - no saved address at all -> the original re-prompt-for-location flow.
  ///  - address already saved, backend just found zero eligible vendors in
  ///    range -> re-prompting for location is nonsensical (it's already set),
  ///    so this instead offers a lightweight "Scan Now" retry that re-queries
  ///    without touching GPS/permissions.
  Widget _buildEmptyVendorState({required bool hasAddress}) {
    if (!hasAddress) {
      return AppEmptyState(
        icon: AppIcons.store,
        title: 'No laundry partners available nearby',
        subtitle: 'Enable location to discover nearby laundry partners.',
        actionLabel: 'Enable Location',
        onAction: () {
          ref.invalidate(homeVendorsProvider);
          requireAuthenticated(
            context: context,
            ref: ref,
            action: (context, _) async {
              final wantsManualEntry = await showLocationCaptureSheet(context);
              if (wantsManualEntry && context.mounted) {
                context.push(AppRoutes.mapAddress);
              }
            },
          );
        },
      );
    }

    return AppEmptyState(
      illustration: _RadarScanIllustration(scanning: _isScanningForVendors),
      title: 'No laundry partners here yet',
      subtitle: 'We scanned your area and couldn\'t find a partner nearby '
          'right now. New partners come online regularly — try again in a bit.',
      actionLabel: _isScanningForVendors ? 'Scanning…' : 'Scan Now',
      onAction: _isScanningForVendors ? null : _scanForNearbyVendors,
    );
  }

  Future<void> _scanForNearbyVendors() async {
    setState(() => _isScanningForVendors = true);
    ref.invalidate(homeVendorsProvider);
    try {
      await ref.read(homeVendorsProvider.future);
    } catch (_) {
      // Surfaced by the provider's own error state; nothing extra to do here.
    }
    if (mounted) setState(() => _isScanningForVendors = false);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Hero Section: home_img.png background behind the header/greeting, with the
// search bar floating over the boundary into the plain-background content
// below it.
// ═════════════════════════════════════════════════════════════════════════════

class _HomeHeroSection extends ConsumerWidget {
  const _HomeHeroSection({required this.addressAsync});

  final AsyncValue<AddressModel?> addressAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final heroHeight = 300.h;
    final searchBarHeight = 52.h;
    final overlap = searchBarHeight / 2;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          children: [
            SizedBox(
              height: heroHeight,
              child: _HomeHeroBackground(addressAsync: addressAsync),
            ),
            SizedBox(height: overlap),
          ],
        ),
        Positioned(
          top: heroHeight - overlap,
          left: 0,
          right: 0,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: _HomeSearchBar(height: searchBarHeight),
          ),
        ),
      ],
    );
  }
}

/// The `home_img.png` hero image, fully visible with no overlay/blur/scrim,
/// with the logo/location/notification/avatar header and greeting text laid
/// directly on top — each rendered via [_OutlinedText] (a slim white stroke)
/// for legibility, since no background wash is used to dim the photo.
class _HomeHeroBackground extends ConsumerWidget {
  const _HomeHeroBackground({required this.addressAsync});

  final AsyncValue<AddressModel?> addressAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topPadding = MediaQuery.paddingOf(context).top;

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/img/home_img.png',
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, topPadding + 12.h, 20.w, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Logo, Location, Notification & Avatar ─────────────────
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _OutlinedText(
                            'Lndry',
                            style: AppTypography.displayMedium.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            fillColor: AppColors.primary,
                            strokeWidth: 2.5,
                          ),
                          const Gap(4),
                          GestureDetector(
                            onTap: () => requireAuthenticated(
                              context: context,
                              ref: ref,
                              returnTo: AppRoutes.mapAddress,
                              action: (context, _) =>
                                  context.push(AppRoutes.mapAddress),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  AppIcons.location,
                                  color: AppColors.primary,
                                  size: 16.r,
                                ),
                                const Gap(4),
                                addressAsync.when(
                                  data: (addr) => Flexible(
                                    child: _OutlinedText(
                                      addr != null
                                          ? '${addr.type.label} · ${addr.line2 != null && addr.line2!.isNotEmpty ? '${addr.line2}, ' : ''}${addr.city}'
                                          : 'Select address',
                                      style: AppTypography.labelMedium.copyWith(
                                        fontWeight: FontWeight.w500,
                                      ),
                                      fillColor: AppColors.textBlack,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  loading: () => Container(
                                    width: 120.w,
                                    height: 14.h,
                                    decoration: BoxDecoration(
                                      color: AppColors.shimmerBase,
                                      borderRadius: BorderRadius.circular(4.r),
                                    ),
                                  ),
                                  error: (_, __) => _OutlinedText(
                                    'Select address',
                                    style: AppTypography.labelMedium.copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                                    fillColor: AppColors.textBlack,
                                  ),
                                ),
                                const Gap(4),
                                Icon(
                                  AppIcons.chevronDown,
                                  color: AppColors.textSecondary,
                                  size: 16.r,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Notification badge
                    Stack(
                      children: [
                        _HeroIconButton(
                          icon: AppIcons.notificationsOutlined,
                          onPressed: () => requireAuthenticated(
                            context: context,
                            ref: ref,
                            returnTo: AppRoutes.notifications,
                            action: (context, _) =>
                                context.push(AppRoutes.notifications),
                          ),
                        ),
                        Positioned(
                          top: 6.h,
                          right: 6.w,
                          child: Container(
                            width: 8.r,
                            height: 8.r,
                            decoration: BoxDecoration(
                              color: AppColors.secondary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: AppColors.white, width: 1.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Gap(8),
                    _HeroIconButton(
                      icon: Icons.star_outline_rounded,
                      tooltip: 'Last order & review',
                      onPressed: () => requireAuthenticated(
                        context: context,
                        ref: ref,
                        returnTo: AppRoutes.lastOrderReview,
                        action: (context, _) =>
                            context.push(AppRoutes.lastOrderReview),
                      ),
                    ),
                    const Gap(8),
                    // Avatar
                    GestureDetector(
                      onTap: () => context.go(AppRoutes.profile),
                      child: Builder(builder: (context) {
                        final user = ref.watch(currentUserProvider);
                        final avatarUrl = user?.avatarUrl;
                        final initials = (user?.name ?? '')
                            .trim()
                            .split(' ')
                            .where((p) => p.isNotEmpty)
                            .take(2)
                            .map((p) => p[0].toUpperCase())
                            .join();
                        return CircleAvatar(
                          radius: 20.r,
                          backgroundColor: AppColors.white,
                          child: CircleAvatar(
                            radius: 18.r,
                            backgroundColor: AppColors.primaryContainer,
                            backgroundImage:
                                (avatarUrl != null && avatarUrl.isNotEmpty)
                                    ? NetworkImage(avatarUrl)
                                    : null,
                            child: (avatarUrl == null || avatarUrl.isEmpty)
                                ? Text(
                                    initials.isNotEmpty ? initials : '?',
                                    style: AppTypography.labelSmall.copyWith(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : null,
                          ),
                        );
                      }),
                    ),
                  ],
                ),
                const Gap(20),

                // ── Greeting ────────────────────────────────────────────────
                Builder(builder: (context) {
                  final user = ref.watch(currentUserProvider);
                  final firstName = (user?.name ?? '').trim().split(' ').first;
                  final displayName =
                      firstName.isNotEmpty ? firstName : 'there';
                  final hour = DateTime.now().hour;
                  final greeting = hour < 12
                      ? 'Good morning'
                      : hour < 17
                          ? 'Good afternoon'
                          : 'Good evening';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _OutlinedText(
                        '$greeting, $displayName',
                        style: AppTypography.headlineMedium.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        fillColor: AppColors.textBlack,
                        strokeWidth: 2.5,
                      ),
                      const Gap(4),
                      _OutlinedText(
                        'What would you like us to care for today?',
                        style: AppTypography.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        fillColor: AppColors.textBlack,
                      ),
                    ],
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Text with a slim white outline behind its fill color — legible over any
/// part of the hero photo without a background wash/shadow behind it.
/// [style] must not itself set `color`; pass the fill color separately via
/// [fillColor] so the same style (minus color) can be reused for the stroke
/// layer underneath.
class _OutlinedText extends StatelessWidget {
  const _OutlinedText(
    this.text, {
    required this.style,
    required this.fillColor,
    this.strokeColor = AppColors.white,
    this.strokeWidth = 1.6,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final TextStyle style;
  final Color fillColor;
  final Color strokeColor;
  final double strokeWidth;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Text(
          text,
          maxLines: maxLines,
          overflow: overflow,
          style: style.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = strokeWidth
              ..color = strokeColor,
          ),
        ),
        Text(
          text,
          maxLines: maxLines,
          overflow: overflow,
          style: style.copyWith(color: fillColor),
        ),
      ],
    );
  }
}

/// Small circular white-backed icon button, for legibility sitting directly
/// on the hero image (unlike a plain [IconButton], which would blend into
/// busier parts of the photo).
class _HeroIconButton extends StatelessWidget {
  const _HeroIconButton(
      {required this.icon, required this.onPressed, this.tooltip});

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40.r,
      height: 40.r,
      decoration: BoxDecoration(
        color: AppColors.white,
        shape: BoxShape.circle,
        boxShadow: AppElevation.low,
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(icon, color: AppColors.textBlack, size: 20.r),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}

/// Search bar, unchanged in behavior — just extracted so it can be
/// positioned straddling the hero image's bottom edge from [_HomeHeroSection].
class _HomeSearchBar extends StatelessWidget {
  const _HomeSearchBar({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => StatefulNavigationShell.of(context).goBranch(1),
      child: Container(
        height: height,
        padding: EdgeInsets.only(left: 16.w, right: 8.w),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.full.r),
          border: Border.all(color: AppColors.outlineVariant),
          boxShadow: AppElevation.low,
        ),
        child: Row(
          children: [
            Icon(
              AppIcons.search,
              color: AppColors.textBlack,
              size: 20.r,
            ),
            const Gap(12),
            Expanded(
              child: Text(
                'Search services or nearby laundries',
                style: AppTypography.inputHint.copyWith(
                  color: AppColors.textMuted,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Gap(8),
            GestureDetector(
              onTap: () => StatefulNavigationShell.of(context).goBranch(1),
              child: Container(
                width: 36.r,
                height: 36.r,
                decoration: const BoxDecoration(
                  color: AppColors.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    AppIcons.filter,
                    color: AppColors.primary,
                    size: 18.r,
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

/// Pulsing radar-style illustration for the "scan for nearby vendors" empty
/// state. Animates continuously only while [scanning] is true; otherwise
/// renders a single static ring so the empty state doesn't feel inert.
class _RadarScanIllustration extends StatefulWidget {
  const _RadarScanIllustration({required this.scanning});

  final bool scanning;

  @override
  State<_RadarScanIllustration> createState() => _RadarScanIllustrationState();
}

class _RadarScanIllustrationState extends State<_RadarScanIllustration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.scanning) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _RadarScanIllustration oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scanning && !oldWidget.scanning) {
      _controller.repeat();
    } else if (!widget.scanning && oldWidget.scanning) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const size = 120.0;
    return SizedBox(
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              if (widget.scanning)
                for (final delay in [0.0, 0.33, 0.66])
                  _RadarRing(progress: (_controller.value + delay) % 1.0),
              Container(
                width: 76,
                height: 76,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryContainer,
                ),
                child: const Icon(
                  AppIcons.store,
                  size: 34,
                  color: AppColors.primary,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RadarRing extends StatelessWidget {
  const _RadarRing({required this.progress});

  /// 0.0 (just born, at the store icon) -> 1.0 (fully expanded, faded out).
  final double progress;

  @override
  Widget build(BuildContext context) {
    final scale = 0.55 + (progress * 0.85);
    final opacity = (1.0 - progress).clamp(0.0, 1.0);
    return Opacity(
      opacity: opacity * 0.6,
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.primary, width: 2),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ISSUE 1: Offer Banner Carousel
// ═════════════════════════════════════════════════════════════════════════════

class _OfferBannerCarousel extends ConsumerStatefulWidget {
  const _OfferBannerCarousel();

  @override
  ConsumerState<_OfferBannerCarousel> createState() =>
      _OfferBannerCarouselState();
}

class _OfferBannerCarouselState extends ConsumerState<_OfferBannerCarousel> {
  late final PageController _pageController;
  Timer? _autoScrollTimer;
  int _currentPage = 0;
  int? _autoScrollBannerCount;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
  }

  /// (Re)starts the auto-scroll timer for [bannerCount] banners.
  /// If only one banner, auto-scroll is silently disabled. No-op if the
  /// banner count hasn't changed since the timer was last (re)started.
  void _startAutoScroll(int bannerCount) {
    if (_autoScrollBannerCount == bannerCount) return;
    _autoScrollBannerCount = bannerCount;
    _autoScrollTimer?.cancel();
    if (bannerCount <= 1) return;
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_pageController.hasClients) return;
      final nextPage = (_currentPage + 1) % bannerCount;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _autoScrollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bannersAsync = ref.watch(homeBannersProvider);

    return bannersAsync.when(
      data: (allBanners) {
        // 'offer' banners get their own small strip (see
        // `_SpecialOffersSection`) instead of this main hero carousel.
        final banners =
            allBanners.where((b) => b.bannerType != 'offer').toList();
        if (banners.isEmpty) {
          _autoScrollTimer?.cancel();
          _autoScrollBannerCount = null;
          return const SizedBox.shrink();
        }
        _startAutoScroll(banners.length);
        if (_currentPage >= banners.length) _currentPage = 0;

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                // Matches the backend's banner Cloudinary transform
                // (w_1440,h_720 = 2:1) so a correctly-sized upload renders
                // full-bleed with no cropping.
                aspectRatio: 2,
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (page) => setState(() => _currentPage = page),
                  itemCount: banners.length,
                  itemBuilder: (context, idx) =>
                      _BannerPage(banner: banners[idx]),
                ),
              ),
              const Gap(10),
              // Page indicator dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  banners.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: index == _currentPage ? 18.w : 6.r,
                    height: 6.r,
                    margin: EdgeInsets.symmetric(horizontal: 3.w),
                    decoration: BoxDecoration(
                      color: index == _currentPage
                          ? AppColors.primary
                          : AppColors.primary.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(AppRadius.full.r),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => Padding(
        padding: EdgeInsets.symmetric(horizontal: 20.w),
        child: AspectRatio(
          aspectRatio: 2,
          child: AppSkeletonCard(
            height: double.infinity,
            borderRadius: AppRadius.xxl.r,
            margin: EdgeInsets.zero,
          ),
        ),
      ),
      // Precedent from homeCategoriesProvider/homeVendorsProvider error cases
      // elsewhere in this file: fail quiet rather than show an error card.
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// Shared tap behavior for any admin-created banner, keyed off
/// [BannerModel.linkType] — used by both the main hero carousel below and
/// the small "Special offers" banner strip (see `_SpecialOffersSection`),
/// so a banner behaves identically regardless of where it's shown.
/// 'category' pushes the category detail route (matching the category-chip
/// navigation elsewhere on this page); 'product' falls back to the browse
/// tab (this app has no dedicated product-detail route yet); 'url' opens
/// the link externally via url_launcher; 'coupon' validates `linkValue` (a
/// coupon code) against the customer's current cart and, on success, hands
/// it to Cart/Checkout the same way applying from the Coupons & Offers page
/// does (see `pendingCouponCodeProvider`'s doc comment); 'none' is inert.
Future<void> _handleBannerTap(
  BuildContext context,
  WidgetRef ref,
  BannerModel banner,
) async {
  switch (banner.linkType) {
    case 'category':
      final categoryId = banner.linkValue;
      if (categoryId != null && categoryId.isNotEmpty) {
        context.push('/category/$categoryId');
      } else {
        StatefulNavigationShell.of(context).goBranch(1);
      }
    case 'product':
      // No dedicated product-detail screen/route exists in this app yet;
      // fall back to the browse/search tab as a reasonable default.
      StatefulNavigationShell.of(context).goBranch(1);
    case 'url':
      final rawUrl = banner.linkValue;
      if (rawUrl == null || rawUrl.isEmpty) return;
      final uri = Uri.tryParse(rawUrl);
      if (uri != null && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    case 'coupon':
      final code = banner.linkValue;
      if (code == null || code.isEmpty) return;
      try {
        final repo = ref.read(customerRepositoryProvider);
        final cartTotal = ref.read(cartStateProvider).total;
        final result = await repo.validateCoupon(code: code, cartTotal: cartTotal);
        if (!context.mounted) return;
        if (result.valid) {
          ref.read(pendingCouponCodeProvider.notifier).state = code;
          AppSnackBar.showSuccess(
            context,
            result.message ?? 'Coupon "$code" applied! It\'ll be ready in your cart.',
          );
        } else {
          AppSnackBar.showError(
            context,
            result.message ?? 'This coupon isn\'t valid for your current cart.',
          );
        }
      } catch (_) {
        if (context.mounted) {
          AppSnackBar.showError(
            context,
            'Could not validate coupon. Please try again.',
          );
        }
      }
    case 'none':
    default:
      break;
  }
}

/// Renders a single backend-driven promotional banner in the main hero
/// carousel. See [_handleBannerTap] for tap behavior.
class _BannerPage extends ConsumerWidget {
  const _BannerPage({required this.banner});

  final BannerModel banner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasImage = banner.imageUrl.isNotNullOrBlank;
    final hasSubtitle = banner.subtitle.isNotNullOrBlank;
    final isTappable = banner.linkType != 'none';

    return GestureDetector(
      onTap: isTappable ? () => _handleBannerTap(context, ref, banner) : null,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          // Sensible default gradient background — also the fallback shown
          // when there's no image or it fails to load.
          gradient: const LinearGradient(
            colors: [AppColors.offerLavender, AppColors.secondaryLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppRadius.xxl.r),
          boxShadow: AppElevation.low,
        ),
        // Uploaded banner graphics are complete, self-contained marketing
        // assets (own headline/CTA baked in) at the same 2:1 ratio as this
        // card, so the image fills the card edge-to-edge instead of sharing
        // space with app-rendered title/subtitle text.
        child: hasImage
            ? CachedNetworkImage(
                imageUrl: banner.imageUrl!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                placeholder: (_, __) => const SizedBox.shrink(),
                errorWidget: (_, __, ___) => _BannerFallbackText(
                  title: banner.title,
                  subtitle: hasSubtitle ? banner.subtitle : null,
                ),
              )
            : _BannerFallbackText(
                title: banner.title,
                subtitle: hasSubtitle ? banner.subtitle : null,
              ),
      ),
    );
  }
}

/// Shown in place of the banner image when none is set or it fails to load.
class _BannerFallbackText extends StatelessWidget {
  const _BannerFallbackText({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 18.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: AppTypography.headlineSmall.copyWith(
              color: AppColors.primaryDark,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle.isNotNullOrBlank) ...[
            const Gap(4),
            Text(
              subtitle!,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textBlack,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Quick Book Card ("Book in under a minute")
// ═════════════════════════════════════════════════════════════════════════════

class _QuickScheduleCard extends ConsumerWidget {
  const _QuickScheduleCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addressAsync = ref.watch(currentAddressProvider);
    final addressLabel = addressAsync.when(
      data: (addr) =>
          addr != null ? '${addr.line1}, ${addr.city}' : 'Add address',
      loading: () => 'Loading…',
      error: (_, __) => 'Add address',
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Container(
        padding: EdgeInsets.all(18.r),
        decoration: BoxDecoration(
          gradient: AppColors.signInSheetGradient,
          borderRadius: BorderRadius.circular(AppRadius.xxl.r),
          border: Border.all(
              color: AppColors.white.withValues(alpha: 0.8), width: 1),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.10),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Book in under a minute',
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.lightTextPrimary,
                  ),
                ),
                Gap(4.w),
                Icon(Icons.auto_awesome_rounded,
                    size: 16.r, color: AppColors.primary),
              ],
            ),
            const Gap(16),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 4.h),
              decoration: BoxDecoration(
                color: AppColors.white.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(AppRadius.xl.r),
                border:
                    Border.all(color: AppColors.white.withValues(alpha: 0.85)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _QuickScheduleItem(
                      icon: AppIcons.laundry,
                      tone: Premium3DIconTone.purple,
                      label: 'Service',
                      value: 'Wash & Fold',
                      onTap: () =>
                          StatefulNavigationShell.of(context).goBranch(1),
                    ),
                  ),
                  Container(
                      width: 1, height: 36.h, color: AppColors.outlineVariant),
                  Expanded(
                    child: _QuickScheduleItem(
                      icon: AppIcons.timer,
                      tone: Premium3DIconTone.aqua,
                      label: 'Pickup time',
                      value: 'Today, 6–8 PM',
                      onTap: () =>
                          StatefulNavigationShell.of(context).goBranch(1),
                    ),
                  ),
                  Container(
                      width: 1, height: 36.h, color: AppColors.outlineVariant),
                  Expanded(
                    child: _QuickScheduleItem(
                      icon: AppIcons.location,
                      tone: Premium3DIconTone.purple,
                      label: 'Address',
                      value: addressLabel,
                      onTap: () => context.push(AppRoutes.mapAddress),
                    ),
                  ),
                ],
              ),
            ),
            const Gap(16),
            _GlossyGradientButton(
              label: 'Schedule pickup',
              onTap: () => StatefulNavigationShell.of(context).goBranch(1),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickScheduleItem extends StatelessWidget {
  const _QuickScheduleItem({
    required this.icon,
    required this.tone,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final Premium3DIconTone tone;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 8.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Premium3DIcon(icon: icon, tone: tone, size: 30, iconSize: 15),
            const Gap(8),
            Text(
              label,
              style: AppTypography.caption.copyWith(
                color: AppColors.lightTextSecondary,
                fontSize: 10.sp,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const Gap(1),
            Row(
              children: [
                Flexible(
                  child: Text(
                    value,
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.lightTextPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  AppIcons.chevronDown,
                  size: 12.r,
                  color: AppColors.lightTextSecondary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared premium pill CTA: purple→aqua gradient, glossy top-highlight
/// sweep, soft purple glow, round arrow capsule, and a tap scale-down for
/// tactile feedback. Used by the booking card and the guest benefits CTA.
class _GlossyGradientButton extends StatefulWidget {
  const _GlossyGradientButton(
      {required this.label, required this.onTap, this.height});

  final String label;
  final VoidCallback onTap;
  final double? height;

  @override
  State<_GlossyGradientButton> createState() => _GlossyGradientButtonState();
}

class _GlossyGradientButtonState extends State<_GlossyGradientButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final radius = AppRadius.button.r;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          width: double.infinity,
          height: (widget.height ?? 52).h,
          decoration: BoxDecoration(
            // Mostly-solid purple (not a loud purple->aqua blend) with a
            // defined light border — a clean, readable pill rather than a
            // busy multi-color gradient.
            gradient: const LinearGradient(
              colors: [AppColors.primaryDark, AppColors.primary],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: AppColors.white.withValues(alpha: 0.28),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color:
                    AppColors.primary.withValues(alpha: _pressed ? 0.18 : 0.28),
                blurRadius: _pressed ? 10 : 18,
                offset: Offset(0, _pressed ? 3 : 7),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: (widget.height ?? 52).h * 0.4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(radius)),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.white.withValues(alpha: 0.16),
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
                      widget.label,
                      style: AppTypography.buttonText.copyWith(
                        color: AppColors.white,
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    Gap(AppSpacing.sm.w),
                    Container(
                      width: 24.r,
                      height: 24.r,
                      decoration: BoxDecoration(
                        color: AppColors.white.withValues(alpha: 0.22),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 14.r,
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

// ═════════════════════════════════════════════════════════════════════════════
// Guest Home State: "Unlock your laundry benefits" — replaces the confusing
// "no laundry partners nearby" empty state for a guest who hasn't signed in
// (and therefore has no address/location to match vendors against yet).
// ═════════════════════════════════════════════════════════════════════════════

class _GuestBenefitsSection extends StatelessWidget {
  const _GuestBenefitsSection(
      {required this.onSignIn, required this.onContinueAsGuest});

  final VoidCallback onSignIn;
  final VoidCallback onContinueAsGuest;

  static const _benefits = [
    _Benefit(
        icon: Icons.bolt_rounded,
        tone: Premium3DIconTone.purple,
        title: 'Faster booking',
        helper: 'One-tap reorders'),
    _Benefit(
        icon: AppIcons.location,
        tone: Premium3DIconTone.aqua,
        title: 'Save addresses',
        helper: 'For quick checkout'),
    _Benefit(
        icon: Icons.inventory_2_rounded,
        tone: Premium3DIconTone.purple,
        title: 'Track orders',
        helper: 'Real-time updates'),
    _Benefit(
        icon: AppIcons.tag,
        tone: Premium3DIconTone.aqua,
        title: 'Exclusive offers',
        helper: 'Members only deals'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: AppColors.signInSheetGradient,
          borderRadius: BorderRadius.circular(AppRadius.xxl.r),
          border: Border.all(
              color: AppColors.white.withValues(alpha: 0.8), width: 1),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.10),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Full-width banner — the graphic already carries the "Unlock
            // your laundry benefits" headline + subtitle + brand mark, so
            // nothing is duplicated in app-rendered text on top of it.
            AspectRatio(
              aspectRatio: 2172 / 724,
              child: Image.asset(
                'assets/images/img/Lndry_Laundry_Benefits_Banner.png',
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 18.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      for (var i = 0; i < _benefits.length; i++) ...[
                        if (i > 0) Gap(8.w),
                        Expanded(
                            child: _BenefitMiniCard(benefit: _benefits[i])),
                      ],
                    ],
                  ),
                  const Gap(18),
                  _GlossyGradientButton(
                      label: 'Sign in to continue', onTap: onSignIn),
                  const Gap(8),
                  Center(
                    child: GestureDetector(
                      onTap: onContinueAsGuest,
                      child: RichText(
                        text: TextSpan(
                          style: AppTypography.bodySmall
                              .copyWith(color: AppColors.lightTextSecondary),
                          children: [
                            const TextSpan(text: 'New here? '),
                            TextSpan(
                              text: 'Continue as guest',
                              style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Benefit {
  const _Benefit(
      {required this.icon,
      required this.tone,
      required this.title,
      required this.helper});
  final IconData icon;
  final Premium3DIconTone tone;
  final String title;
  final String helper;
}

/// Compact vertical benefit card: a soft transparent brand-tint circle
/// behind a solid-colored icon (not a solid gradient glossy box) — the
/// icon glyph carries the purple/aqua brand color, the circle behind it
/// stays a translucent tint, matching the reference composition exactly.
class _BenefitMiniCard extends StatelessWidget {
  const _BenefitMiniCard({required this.benefit});
  final _Benefit benefit;

  @override
  Widget build(BuildContext context) {
    final isAqua = benefit.tone == Premium3DIconTone.aqua;
    final accent = isAqua ? AppColors.aquaDeep : AppColors.primary;
    final tintBg = isAqua
        ? AppColors.aqua.withValues(alpha: 0.16)
        : AppColors.primary.withValues(alpha: 0.12);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 4.w),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44.r,
            height: 44.r,
            decoration: BoxDecoration(color: tintBg, shape: BoxShape.circle),
            child: Icon(benefit.icon, color: accent, size: 20.r),
          ),
          Gap(8.h),
          Text(
            benefit.title,
            textAlign: TextAlign.center,
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.lightTextPrimary,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Gap(1.h),
          Text(
            benefit.helper,
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(
              color: AppColors.lightTextSecondary,
              fontSize: 9.sp,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Authenticated-but-no-location: compact permission card (not a full-screen
// empty state) shown inline where "Recommended near you" would otherwise go.
// ═════════════════════════════════════════════════════════════════════════════

class _LocationPermissionCompactCard extends StatelessWidget {
  const _LocationPermissionCompactCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(14.r),
        decoration: BoxDecoration(
          gradient: AppColors.signInSheetGradient,
          borderRadius: BorderRadius.circular(AppRadius.xl.r),
          border: Border.all(color: AppColors.white.withValues(alpha: 0.8)),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            const Premium3DIcon(
                icon: AppIcons.location,
                tone: Premium3DIconTone.aqua,
                size: 40,
                iconSize: 20),
            Gap(12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Enable location',
                    style: AppTypography.titleSmall.copyWith(
                      color: AppColors.lightTextPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Gap(2.h),
                  Text(
                    'See laundry partners near you',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(AppIcons.chevronRight, size: 20.r, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Active Order Tracker Card
// ═════════════════════════════════════════════════════════════════════════════

class _ActiveOrderTrackerCard extends StatelessWidget {
  const _ActiveOrderTrackerCard({
    required this.order,
    required this.currentStep,
    required this.statusText,
  });
  final OrderModel order;
  final int currentStep;
  final String statusText;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card.r),
        boxShadow: AppElevation.low,
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 5.w,
              decoration: BoxDecoration(
                color: AppColors.secondary,
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(AppRadius.card.r),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(16.r),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        'Order #${order.orderNumber.isNotEmpty ? order.orderNumber : order.id.toUpperCase()}',
                        style: AppTypography.caption
                            .copyWith(color: AppColors.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => context.push('/orders/details/${order.id}'),
                      child: Text(
                        'Track',
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const Gap(8),
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(8.r),
                      decoration: const BoxDecoration(
                        color: AppColors.secondaryLight,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        AppIcons.laundry,
                        color: AppColors.secondary,
                        size: 20.r,
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            statusText,
                            style: AppTypography.titleSmall.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.textBlack,
                            ),
                          ),
                          Text(
                            '${order.items.length} items · ${order.items.isNotEmpty ? order.items.first.serviceName : 'Laundry'}',
                            style: AppTypography.bodySmall
                                .copyWith(color: AppColors.textSecondary),
                          ),
                          Text(
                            order.estimatedDeliveryAt?.toDayDate ??
                                'Delivery estimate pending',
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.success,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Gap(20),
                const AppDivider(),
                const Gap(16),
                _ActiveOrderTimelineRow(currentStep: currentStep),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveOrderTimelineRow extends StatelessWidget {
  const _ActiveOrderTimelineRow({required this.currentStep});
  final int currentStep;

  @override
  Widget build(BuildContext context) {
    const List<String> steps = [
      'Picked up',
      'Cleaning',
      'Quality check',
      'Out for delivery',
    ];

    return Row(
      children: List.generate(
        steps.length,
        (index) {
          final isCompleted = index <= currentStep;
          final isCurrent = index == currentStep;
          final showLine = index < steps.length - 1;

          return Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: isCurrent ? 16.r : 14.r,
                      height: isCurrent ? 16.r : 14.r,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isCompleted
                            ? AppColors.secondary
                            : AppColors.outlineVariant,
                      ),
                      child: isCompleted && index == 0
                          ? Center(
                              child: Icon(
                                AppIcons.done,
                                color: AppColors.white,
                                size: 8.r,
                              ),
                            )
                          : null,
                    ),
                    if (showLine)
                      Expanded(
                        child: Container(
                          height: 2.h,
                          color: isCompleted
                              ? AppColors.secondary
                              : AppColors.outlineVariant,
                        ),
                      ),
                  ],
                ),
                const Gap(6),
                Padding(
                  padding: EdgeInsets.only(right: 8.w),
                  child: Text(
                    steps[index],
                    style: AppTypography.caption.copyWith(
                      fontSize: 8.sp,
                      fontWeight:
                          isCurrent ? FontWeight.bold : FontWeight.normal,
                      color: isCompleted
                          ? AppColors.secondary
                          : AppColors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Horizontal Vendor Card ("Recommended near you")
// ═════════════════════════════════════════════════════════════════════════════

class _HorizontalVendorCard extends StatelessWidget {
  const _HorizontalVendorCard({required this.vendor, required this.onTap});
  final VendorModel vendor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final double displayDistance =
        vendor.distanceKm ?? ((vendor.id.hashCode.abs() % 20) + 5) / 10;

    return AppCard.outlined(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.horizontal(
              left: Radius.circular(AppRadius.card.r),
            ),
            child: Container(
              width: 115.w,
              height: double.infinity,
              color: AppColors.shimmerBase,
              child: Hero(
                tag: 'vendor-cover-${vendor.id}',
                child: Material(
                  type: MaterialType.transparency,
                  child: vendor.coverImageUrl.isNotNullOrBlank
                      ? CachedNetworkImage(
                          imageUrl: vendor.coverImageUrl!,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          color: AppColors.primaryContainer,
                          child: Icon(
                            AppIcons.store,
                            size: 32.r,
                            color: AppColors.primary,
                          ),
                        ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(12.r),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vendor.name,
                        style: AppTypography.titleSmall.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textBlack,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Gap(4),
                      Row(
                        children: [
                          Icon(
                            AppIcons.star,
                            color: AppColors.rating,
                            size: 13.r,
                          ),
                          const Gap(4),
                          Expanded(
                            child: Text(
                              '${vendor.averageRating ?? 4.8} · ${displayDistance.toStringAsFixed(1)} km',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          'From ${vendor.minOrderAmount.toCurrency}/kg',
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        'Pickup in 30 min',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.secondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _ServicePill(label: 'Wash & Fold'),
                        Gap(4),
                        _ServicePill(label: 'Dry Clean'),
                        Gap(4),
                        _ServicePill(label: '+3'),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (vendor.isVerified)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              AppIcons.success,
                              color: AppColors.secondary,
                              size: 13.r,
                            ),
                            const Gap(4),
                            Text(
                              'Verified',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.secondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        )
                      else
                        const SizedBox.shrink(),
                      Container(
                        padding: EdgeInsets.all(6.r),
                        decoration: const BoxDecoration(
                          color: AppColors.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          AppIcons.forward,
                          color: AppColors.primary,
                          size: 12.r,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServicePill extends StatelessWidget {
  const _ServicePill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(4.r),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          fontSize: 9.sp,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ISSUE 4: Special Offers Section — small admin-managed banners
// (bannerType == 'offer' from the same Banners admin page/GET /banners the
// main hero carousel above uses), replacing the previous hardcoded
// IRONFREE/DRYCLEAN20 cards and, before that, a raw coupon-list rendering.
// An admin picks the image/copy and, per banner, what tapping it does —
// apply a specific coupon, open a category, an external URL, or nothing —
// via the same linkType/linkValue the hero carousel already uses (see
// `_handleBannerTap`). Hidden entirely when there are no 'offer' banners
// right now rather than showing an empty heading.
// ═════════════════════════════════════════════════════════════════════════════

class _SpecialOffersSection extends ConsumerWidget {
  const _SpecialOffersSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bannersAsync = ref.watch(homeBannersProvider);

    return bannersAsync.maybeWhen(
      data: (allBanners) {
        final offerBanners =
            allBanners.where((b) => b.bannerType == 'offer').toList();
        if (offerBanners.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Special offers',
                      style: AppTypography.titleLarge.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textBlack,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => context.push(AppRoutes.offers),
                    child: Text(
                      'View all',
                      style: AppTypography.labelMedium
                          .copyWith(color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            ),
            const Gap(12),
            SizedBox(
              height: 100.h,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                clipBehavior: Clip.none,
                itemCount: offerBanners.length,
                separatorBuilder: (_, __) => const Gap(16),
                itemBuilder: (context, i) =>
                    _OfferBannerCard(banner: offerBanners[i]),
              ),
            ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

/// A single small "offer" banner card — real admin-uploaded image, tap
/// behavior fully driven by [BannerModel.linkType]/`linkValue` via
/// [_handleBannerTap] (same as the main hero carousel's `_BannerPage`,
/// just a smaller card shape suited to a horizontal strip).
class _OfferBannerCard extends ConsumerWidget {
  const _OfferBannerCard({required this.banner});

  final BannerModel banner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasImage = banner.imageUrl.isNotNullOrBlank;
    final hasSubtitle = banner.subtitle.isNotNullOrBlank;
    final isTappable = banner.linkType != 'none';

    return GestureDetector(
      onTap: isTappable ? () => _handleBannerTap(context, ref, banner) : null,
      child: Container(
        width: 250.w,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.offerLavender, AppColors.secondaryLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppRadius.card.r),
          boxShadow: AppElevation.low,
        ),
        child: hasImage
            ? CachedNetworkImage(
                imageUrl: banner.imageUrl!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                placeholder: (_, __) => const SizedBox.shrink(),
                errorWidget: (_, __, ___) => _BannerFallbackText(
                  title: banner.title,
                  subtitle: hasSubtitle ? banner.subtitle : null,
                ),
              )
            : _BannerFallbackText(
                title: banner.title,
                subtitle: hasSubtitle ? banner.subtitle : null,
              ),
      ),
    );
  }
}
