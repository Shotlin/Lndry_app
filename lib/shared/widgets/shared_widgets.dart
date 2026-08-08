import '../../core/design/design_system.dart';

/// A reusable section header with optional "See All" action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.padding,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.titleMedium),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            GestureDetector(
              onTap: onAction,
              child: Text(
                actionLabel!,
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Horizontal divider with optional label
class AppDivider extends StatelessWidget {
  const AppDivider({super.key, this.label, this.padding});

  final String? label;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    if (label == null) {
      return Divider(
        color: AppColors.outlineVariant,
        thickness: 1,
        height: 1,
      );
    }

    return Padding(
      padding: padding ?? EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        children: [
          Expanded(child: Divider(color: AppColors.outlineVariant)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            child: Text(
              label!,
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Divider(color: AppColors.outlineVariant)),
        ],
      ),
    );
  }
}

/// Status badge chip (e.g., for order status).
/// Set [large] = true for full-width prominent status display.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.backgroundColor,
    this.large = false,
  });

  final String label;
  final Color color;
  final Color? backgroundColor;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: large
          ? EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h)
          : EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: backgroundColor ?? color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppRadius.full.r),
        border: large ? Border.all(color: color.withOpacity(0.3)) : null,
      ),
      child: Text(
        label,
        style: (large ? AppTypography.labelLarge : AppTypography.badge)
            .copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// A rating row with star icon
class RatingRow extends StatelessWidget {
  const RatingRow({
    super.key,
    required this.rating,
    this.reviewCount,
    this.starSize,
    this.style,
  });

  final double rating;
  final int? reviewCount;
  final double? starSize;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(AppIcons.star, color: AppColors.rating, size: starSize ?? 16.r),
        SizedBox(width: 3.w),
        Text(
          rating.toStringAsFixed(1),
          style: style ?? AppTypography.labelMedium,
        ),
        if (reviewCount != null) ...[
          SizedBox(width: 3.w),
          Text(
            '($reviewCount)',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// Price summary card showing subtotal, platform fee, GST and total.
/// Used on the cart, checkout, and order detail screens.
class PriceCard extends StatelessWidget {
  const PriceCard({
    super.key,
    required this.subtotal,
    required this.platformFee,
    required this.gstAmount,
    required this.total,
    this.deliveryFee,
    this.amountPaid,
    this.statusText,
    this.isFinalBill = false,
    this.padding,
  });

  final double subtotal;
  /// Combines the vendor's platform fee with any other bundled fee (e.g.
  /// handling) the backend already folds into `total` — kept as one row so
  /// the breakdown always sums to `total` without listing every fee
  /// component individually.
  final double platformFee;
  final double gstAmount;
  final double total;
  /// When provided, shown as its own "Delivery Charge" row.
  final double? deliveryFee;
  /// When provided (order-details context, not checkout), shows the ₹50
  /// booking advance already paid and the remaining payable amount below
  /// the total — subtotal here is the latest evaluated subtotal (post
  /// rider/vendor re-evaluation if either happened), never just a raw
  /// unrevised estimate.
  final double? amountPaid;
  /// Right-aligned status text in the header, e.g. "Vendor Re-evaluation
  /// Done" — lets the customer see at a glance whether this breakdown is
  /// still subject to change.
  final String? statusText;
  /// When true, highlights this card as the order's final, authoritative
  /// bill (shown once the vendor's re-evaluation is in).
  final bool isFinalBill;
  final EdgeInsetsGeometry? padding;

  String _fmt(double v) => '₹${v.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final paid = amountPaid;
    final remaining = paid != null ? (total - paid).clamp(0, double.infinity) : null;
    return Container(
      padding: padding ?? EdgeInsets.all(AppSpacing.md.w),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card.r),
        border: Border.all(
          color: isFinalBill ? AppColors.success : AppColors.outlineVariant,
          width: isFinalBill ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isFinalBill) ...[
            Text(
              'FINAL BILL',
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.success,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            Gap(4.h),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text('Price Details', style: AppTypography.titleSmall),
              ),
              if (statusText != null)
                Text(
                  statusText!,
                  textAlign: TextAlign.end,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          Gap(AppSpacing.sm.h),
          _PriceRow(label: 'Evaluated Subtotal', value: _fmt(subtotal)),
          Gap(AppSpacing.xs.h),
          _PriceRow(label: 'Platform Fee', value: _fmt(platformFee)),
          if (deliveryFee != null) ...[
            Gap(AppSpacing.xs.h),
            _PriceRow(label: 'Delivery Charge', value: _fmt(deliveryFee!)),
          ],
          Gap(AppSpacing.xs.h),
          _PriceRow(label: 'GST', value: _fmt(gstAmount)),
          Gap(AppSpacing.sm.h),
          Divider(color: AppColors.outlineVariant, thickness: 1, height: 1),
          Gap(AppSpacing.sm.h),
          _PriceRow(
            label: 'Total',
            value: _fmt(total),
            labelStyle: AppTypography.titleSmall,
            valueStyle: AppTypography.titleSmall.copyWith(
              color: AppColors.primary,
            ),
          ),
          if (paid != null && remaining != null) ...[
            Gap(AppSpacing.sm.h),
            Divider(color: AppColors.outlineVariant, thickness: 1, height: 1),
            Gap(AppSpacing.sm.h),
            _PriceRow(label: 'Booking Advance Paid', value: _fmt(paid), valueStyle: TextStyle(color: AppColors.success)),
            Gap(AppSpacing.xs.h),
            _PriceRow(
              label: 'Remaining Payable',
              value: _fmt(remaining.toDouble()),
              labelStyle: AppTypography.titleSmall,
              valueStyle: AppTypography.titleSmall.copyWith(
                color: remaining > 0 ? AppColors.warning : AppColors.success,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Internal helper row used by [PriceCard].
class _PriceRow extends StatelessWidget {
  const _PriceRow({
    required this.label,
    required this.value,
    this.labelStyle,
    this.valueStyle,
  });

  final String label;
  final String value;
  final TextStyle? labelStyle;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    final defaultStyle = AppTypography.bodySmall.copyWith(
      color: AppColors.onSurfaceVariant,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: labelStyle ?? defaultStyle),
        Text(value, style: valueStyle ?? defaultStyle),
      ],
    );
  }
}
