import '../design/design_system.dart';
import '../../features/cart/presentation/providers/cart_providers.dart';
import '../../repositories/abstract/customer_repository.dart';

/// Floating "milestone perks" card shown above the bottom nav pill once the
/// customer has added something to their cart — mirrors the tiered
/// spend-more-unlock-more pattern from the reference design, driven by the
/// real Cart Milestones admin data (see cart_providers.dart) rather than
/// hardcoded tiers. Cart Milestones apply to every order (not just a
/// customer's first, unlike First-Time Offers), matching the "spend more,
/// unlock more" pattern for every customer. Renders nothing (not even a
/// placeholder) whenever there are no active/eligible tiers or the cart
/// is empty.
class MilestonePerksCard extends ConsumerWidget {
  const MilestonePerksCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartStateProvider);
    if (cart.totalQuantity == 0) return const SizedBox.shrink();

    final tiersAsync = ref.watch(cartMilestoneTiersProvider);
    return tiersAsync.when(
      data: (tiers) {
        if (tiers.isEmpty) return const SizedBox.shrink();
        return _MilestoneCardContent(
          subtotal: cart.subtotal,
          tiers: tiers,
          vendorId: cart.vendor?.id,
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _MilestoneCardContent extends StatelessWidget {
  const _MilestoneCardContent({
    required this.subtotal,
    required this.tiers,
    required this.vendorId,
  });

  final double subtotal;
  final List<CartMilestoneTier> tiers;
  final String? vendorId;

  /// Branded 3D icon assets (assets/icons/) — already glossy/illustrated in
  /// their own right, so _TierColumn renders these directly rather than
  /// wrapping them in Premium3DIcon's gradient chip (which is for flat
  /// Material glyphs, not pre-rendered art).
  static String _imageFor(String rewardType) {
    switch (rewardType) {
      case 'COUPON_UNLOCK':
        return 'assets/icons/lndry_cupon.png';
      case 'FLAT_DISCOUNT':
      default:
        return 'assets/icons/lndry_gift_box.png';
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxAmount = tiers.last.minOrderAmount;
    final fraction = maxAmount <= 0 ? 1.0 : (subtotal / maxAmount).clamp(0.0, 1.0);
    final nextTier = tiers.cast<CartMilestoneTier?>().firstWhere(
          (t) => subtotal < t!.minOrderAmount,
          orElse: () => null,
        );
    final remaining = nextTier == null ? 0.0 : nextTier.minOrderAmount - subtotal;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 0),
      padding: EdgeInsets.fromLTRB(18.w, 16.h, 18.w, 16.h),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.card.r),
        boxShadow: AppElevation.high,
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                nextTier == null ? 'All perks unlocked!' : 'Unlock laundry perks',
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textBlack,
                ),
              ),
              Gap(4.w),
              Icon(
                nextTier == null
                    ? Icons.celebration_rounded
                    : Icons.auto_awesome_rounded,
                size: 16.r,
                color: AppColors.primary,
              ),
            ],
          ),
          Gap(2.h),
          Text(
            nextTier == null
                ? 'You\'ve unlocked every reward on this order'
                : 'Add more to unlock exciting rewards',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          Gap(16.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final tier in tiers)
                Expanded(
                  child: _TierColumn(
                    achieved: subtotal >= tier.minOrderAmount,
                    imagePath: _imageFor(tier.rewardType),
                    amountLabel: '₹${tier.minOrderAmount.toStringAsFixed(0)}',
                    name: tier.name,
                  ),
                ),
            ],
          ),
          Gap(18.h),
          _MilestoneTrack(fraction: fraction, tiers: tiers, maxAmount: maxAmount),
          Gap(16.h),
          if (nextTier != null)
            Row(
              children: [
                Expanded(
                  child: RichText(
                    text: _nextTierMessage(nextTier, remaining),
                  ),
                ),
                Gap(10.w),
                _AddItemsButton(vendorId: vendorId),
              ],
            ),
        ],
      ),
    );
  }

  /// Prefers the admin-authored `messageBefore` over a generated fallback,
  /// so admins can customize the copy per milestone without a client
  /// release. The dashboard's editor documents two placeholders —
  /// `{amount}` and `{name}` (see CartMilestoneDialog.tsx) — substituted
  /// here; `{amount}` is highlighted, `{name}` is plain inline text.
  static TextSpan _nextTierMessage(CartMilestoneTier tier, double remaining) {
    final baseStyle =
        AppTypography.bodySmall.copyWith(color: AppColors.textSecondary);
    final amountStyle = TextStyle(
      color: AppColors.primary,
      fontWeight: FontWeight.w700,
    );
    final amountText = '₹${remaining.toStringAsFixed(0)}';

    final template = tier.messageBefore?.replaceAll('{name}', tier.name);
    if (template != null && template.contains('{amount}')) {
      final parts = template.split('{amount}');
      return TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: parts[0]),
          TextSpan(text: amountText, style: amountStyle),
          TextSpan(text: parts.sublist(1).join(amountText)),
        ],
      );
    }

    return TextSpan(
      style: baseStyle,
      children: [
        const TextSpan(text: 'Add '),
        TextSpan(text: amountText, style: amountStyle),
        TextSpan(text: ' more to unlock ${tier.name}'),
      ],
    );
  }
}

class _TierColumn extends StatelessWidget {
  const _TierColumn({
    required this.achieved,
    required this.imagePath,
    required this.amountLabel,
    required this.name,
  });

  final bool achieved;
  final String imagePath;
  final String amountLabel;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Opacity(
              opacity: achieved ? 1.0 : 0.45,
              child: Image.asset(imagePath, width: 44.r, height: 44.r),
            ),
            if (achieved)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 10,
                      color: AppColors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
        Gap(6.h),
        Text(
          amountLabel,
          style: AppTypography.bodyMedium.copyWith(
            fontWeight: FontWeight.w700,
            color: achieved ? AppColors.primary : AppColors.textBlack,
          ),
        ),
        Text(
          name,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _MilestoneTrack extends StatelessWidget {
  const _MilestoneTrack({
    required this.fraction,
    required this.tiers,
    required this.maxAmount,
  });

  final double fraction;
  final List<CartMilestoneTier> tiers;
  final double maxAmount;

  @override
  Widget build(BuildContext context) {
    const trackHeight = 6.0;
    const thumbSize = 16.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return SizedBox(
          height: thumbSize,
          width: width,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: fraction),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) {
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: (thumbSize - trackHeight) / 2,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: trackHeight,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(trackHeight / 2),
                      ),
                    ),
                  ),
                  Positioned(
                    top: (thumbSize - trackHeight) / 2,
                    left: 0,
                    width: (width * value).clamp(trackHeight, width),
                    child: Container(
                      height: trackHeight,
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(trackHeight / 2),
                      ),
                    ),
                  ),
                  for (final tier in tiers)
                    if (maxAmount > 0)
                      Positioned(
                        left: (tier.minOrderAmount / maxAmount * width)
                                .clamp(0, width - 8) -
                            4,
                        top: (thumbSize - 8) / 2,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: value * maxAmount >= tier.minOrderAmount
                                ? AppColors.primary
                                : AppColors.white,
                            border: Border.all(
                              color: AppColors.primary,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                  Positioned(
                    left: (width * value - thumbSize / 2)
                        .clamp(0, width - thumbSize),
                    top: 0,
                    child: Container(
                      width: thumbSize,
                      height: thumbSize,
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.primary, width: 2),
                        boxShadow: AppElevation.low,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _AddItemsButton extends StatelessWidget {
  const _AddItemsButton({required this.vendorId});

  final String? vendorId;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (vendorId != null) {
          context.push('/vendor/$vendorId');
        } else {
          StatefulNavigationShell.of(context).goBranch(1);
        }
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primaryDark, AppColors.primary],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(AppRadius.button.r),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.28),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add_shopping_cart_rounded,
                size: 16, color: AppColors.white),
            Gap(6.w),
            Text(
              'Add items',
              style: AppTypography.labelLarge.copyWith(
                color: AppColors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
