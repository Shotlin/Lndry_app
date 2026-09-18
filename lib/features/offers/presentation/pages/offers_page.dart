import 'package:flutter/services.dart';

import '../../../../core/design/design_system.dart';
import '../../../../core/extensions/extensions.dart';
import '../../../../core/network/network.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../repositories/repositories.dart';
import '../../../cart/presentation/providers/cart_providers.dart';
import '../providers/offers_providers.dart';

/// Dedicated "Coupons & Offers" page — reachable from Profile and from a
/// "View all" link on Checkout's coupon section. Lists every coupon the
/// customer is currently eligible for (real backend data, not the
/// hardcoded IRONFREE/DRYCLEAN20 cards that used to live on Home), lets
/// them copy a code or apply it directly (validated live against their
/// current cart total so they see immediately whether it actually works,
/// not just whether it exists), and surfaces the first-order offer when
/// they still qualify for one.
class OffersPage extends ConsumerStatefulWidget {
  const OffersPage({super.key});

  @override
  ConsumerState<OffersPage> createState() => _OffersPageState();
}

class _OffersPageState extends ConsumerState<OffersPage> {
  String? _applyingCouponId;

  Future<void> _applyCoupon(CouponSummary coupon) async {
    if (_applyingCouponId != null) return;
    setState(() => _applyingCouponId = coupon.id);

    try {
      final repo = ref.read(customerRepositoryProvider);
      final cartTotal = ref.read(cartStateProvider).total;
      final result = await repo.validateCoupon(
        code: coupon.code,
        cartTotal: cartTotal,
      );
      if (!mounted) return;

      if (result.valid) {
        // Cart and Checkout each own their own coupon-field state
        // independently — this is how an applied-from-here code reaches
        // whichever of the two the customer opens next (see their
        // initState, which consumes and clears this).
        ref.read(pendingCouponCodeProvider.notifier).state = coupon.code;
        AppSnackBar.showSuccess(
          context,
          result.message ?? 'Coupon applied! It\'ll be ready in your cart.',
        );
        // Hand control back to wherever this page was opened from (Checkout,
        // Cart, or Profile) so the code above is actually picked up right
        // away, instead of leaving the customer stranded here with no
        // indication the applied coupon is now just sitting in the
        // background — a brief pause first so the success toast above is
        // still readable before the page transitions away.
        if (context.canPop()) {
          await Future<void>.delayed(const Duration(milliseconds: 600));
          if (mounted && context.canPop()) context.pop();
        }
      } else {
        AppSnackBar.showError(
          context,
          result.message ?? 'This coupon isn\'t valid for your current cart.',
        );
      }
    } on ApiException catch (e) {
      if (mounted) AppSnackBar.showError(context, e.message);
    } catch (_) {
      if (mounted) {
        AppSnackBar.showError(
          context,
          'Could not validate coupon. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _applyingCouponId = null);
    }
  }

  void _copyCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    AppSnackBar.showInfo(context, 'Code "$code" copied');
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final isDark = theme.brightness == Brightness.dark;
    final couponsAsync = ref.watch(availableCouponsProvider);
    final firstTimeAsync = ref.watch(firstTimeOfferProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Coupons & Offers', style: AppTypography.titleLarge),
        centerTitle: true,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.surface,
        elevation: 0,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(availableCouponsProvider);
            ref.invalidate(firstTimeOfferProvider);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(AppSpacing.pagePaddingH.w),
            children: [
              firstTimeAsync.maybeWhen(
                data: (offer) => offer.eligible && offer.tiers.isNotEmpty
                    ? Padding(
                        padding: EdgeInsets.only(bottom: AppSpacing.md.h),
                        child: _FirstTimeOfferCard(tier: offer.tiers.first),
                      )
                    : const SizedBox.shrink(),
                orElse: () => const SizedBox.shrink(),
              ),
              Text('Available Coupons', style: AppTypography.titleMedium),
              Gap(AppSpacing.cardGap.h),
              couponsAsync.when(
                data: (coupons) => coupons.isEmpty
                    ? const AppEmptyState(
                        icon: AppIcons.coupon,
                        title: 'No coupons right now',
                        subtitle: 'Check back soon — new offers show up here.',
                      )
                    : Column(
                        children: coupons
                            .map((c) => Padding(
                                  padding:
                                      EdgeInsets.only(bottom: AppSpacing.md.h),
                                  child: _CouponCard(
                                    coupon: c,
                                    isApplying: _applyingCouponId == c.id,
                                    onApply: () => _applyCoupon(c),
                                    onCopy: () => _copyCode(c.code),
                                  ),
                                ))
                            .toList(),
                      ),
                loading: () => Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl.h),
                  child: const Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => AppErrorWidget(
                  message: 'Couldn\'t load coupons.',
                  onRetry: () => ref.invalidate(availableCouponsProvider),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FirstTimeOfferCard extends StatelessWidget {
  const _FirstTimeOfferCard({required this.tier});

  final CartMilestoneTier tier;

  String get _rewardLabel => switch (tier.rewardType) {
        'PERCENTAGE_DISCOUNT' =>
          '${tier.rewardValue?.toStringAsFixed(0) ?? ''}% off your first order',
        'FLAT_DISCOUNT' => '₹${tier.rewardValue?.toStringAsFixed(0) ?? ''} off your first order',
        'FREE_DELIVERY' => 'Free delivery on your first order',
        'COUPON_UNLOCK' => 'Unlocks a bonus coupon on your first order',
        _ => tier.name,
      };

  @override
  Widget build(BuildContext context) {
    return AppCard.outlined(
      backgroundColor: AppColors.primaryContainer,
      borderColor: AppColors.primary.withValues(alpha: 0.2),
      child: Row(
        children: [
          Icon(Icons.celebration_rounded, color: AppColors.primary, size: 26.r),
          Gap(AppSpacing.cardGap.h),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome offer — just for you',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Gap(2.h),
                Text(
                  _rewardLabel,
                  style: AppTypography.titleSmall.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Gap(2.h),
                Text(
                  'Applied automatically at checkout — no code needed.',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CouponCard extends StatelessWidget {
  const _CouponCard({
    required this.coupon,
    required this.isApplying,
    required this.onApply,
    required this.onCopy,
  });

  final CouponSummary coupon;
  final bool isApplying;
  final VoidCallback onApply;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return AppCard.outlined(
      backgroundColor: isDark ? AppColors.darkSurfaceContainer : AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      coupon.discountSummary,
                      style: AppTypography.titleMedium.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    if (coupon.description != null) ...[
                      Gap(2.h),
                      Text(
                        coupon.description!,
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              GestureDetector(
                onTap: onCopy,
                child: Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm.w, vertical: AppSpacing.xs.h),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    borderRadius: BorderRadius.circular(AppRadius.input.r),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        coupon.code,
                        style: AppTypography.labelMedium.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                          letterSpacing: 1,
                        ),
                      ),
                      Gap(4.w),
                      Icon(AppIcons.copy, size: 14.r, color: AppColors.primary),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Gap(AppSpacing.sm.h),
          Wrap(
            spacing: AppSpacing.sm.w,
            runSpacing: 4.h,
            children: [
              if (coupon.minOrderAmount > 0)
                _InfoChip(
                    label:
                        'Min order ₹${coupon.minOrderAmount.toStringAsFixed(0)}'),
              if (coupon.maxDiscount != null)
                _InfoChip(
                    label:
                        'Up to ₹${coupon.maxDiscount!.toStringAsFixed(0)}'),
              if (coupon.validUntil != null)
                _InfoChip(label: 'Valid till ${coupon.validUntil!.toDayDate}'),
            ],
          ),
          Gap(AppSpacing.md.h),
          AppButton(
            label: 'Apply',
            isLoading: isApplying,
            isDisabled: isApplying,
            onPressed: onApply,
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.input.r),
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
      ),
    );
  }
}
