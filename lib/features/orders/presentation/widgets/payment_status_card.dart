import '../../../../core/design/design_system.dart';
import '../../../../core/extensions/extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../models/models.dart';
import '../../../../shared/widgets/shared_widgets.dart';

/// Plain-language "how has this order actually been paid" summary —
/// replaces a single flat "Payment: X / Paid|Unpaid" row, which could only
/// ever describe the checkout-time COD-vs-online choice, never which
/// method actually settled each leg (advance and balance can genuinely
/// differ — e.g. advance via Razorpay, balance via the LNDRY wallet) and
/// showed "Unpaid" for an order that had already had its ₹50 advance
/// collected, with no indication of that at all.
class PaymentStatusCard extends StatelessWidget {
  const PaymentStatusCard({super.key, required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final cardColor =
        isDark ? AppColors.darkSurfaceContainer : AppColors.surface;

    if (order.payments.isEmpty) {
      // Orders placed before this field existed — fall back to the old,
      // still-accurate-for-COD single-row summary rather than show nothing.
      return AppCard.outlined(
        backgroundColor: cardColor,
        child: Row(
          children: [
            Icon(AppIcons.payment, color: AppColors.primary, size: 20.r),
            Gap(AppSpacing.cardGap.h),
            Expanded(
              child: Text('Payment: ${order.paymentMethod.label}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelMedium),
            ),
            Gap(AppSpacing.cardGap.h),
            StatusBadge(
              label: order.isPaid ? 'Paid' : 'Unpaid',
              color: order.isPaid ? AppColors.success : AppColors.warning,
            ),
          ],
        ),
      );
    }

    final advance = _latest(OrderPaymentPurpose.advance);
    // A legacy pre-advance-payment order paid everything as one FULL leg —
    // shown the same way an advance would be, since there's no separate
    // balance to speak of.
    final balance = _latest(OrderPaymentPurpose.balance) ??
        (advance == null ? _latest(OrderPaymentPurpose.full) : null);
    final isCod = order.paymentMethod == PaymentMethod.cod;

    return AppCard.outlined(
      backgroundColor: cardColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.payment, color: AppColors.primary, size: 20.r),
              Gap(AppSpacing.cardGap.h),
              Text('Payment', style: AppTypography.labelMedium),
            ],
          ),
          Gap(AppSpacing.sm.h),
          if (advance != null)
            _PaymentLegRow(
              label: advance.purpose == OrderPaymentPurpose.full
                  ? 'Order Payment'
                  : 'Advance',
              amount: advance.amount,
              isPaid: advance.isPaid,
              methodLabel: advance.isPaid ? advance.method?.label : null,
              pendingNote: advance.isPaid ? null : 'Processing...',
            ),
          if (advance != null && balance != null) Gap(AppSpacing.sm.h),
          if (balance != null)
            _PaymentLegRow(
              label: 'Balance',
              amount: balance.amount,
              isPaid: balance.isPaid,
              methodLabel: balance.isPaid ? balance.method?.label : null,
              pendingNote: balance.isPaid
                  ? null
                  : (isCod
                      ? 'Pay cash to your delivery partner'
                      : 'Pay before delivery'),
            ),
        ],
      ),
    );
  }

  /// Most recent row for [purpose] — a retried/failed attempt followed by a
  /// successful one should show only the successful outcome, not both.
  OrderPaymentModel? _latest(OrderPaymentPurpose purpose) {
    final matches =
        order.payments.where((p) => p.purpose == purpose).toList();
    return matches.isEmpty ? null : matches.last;
  }
}

class _PaymentLegRow extends StatelessWidget {
  const _PaymentLegRow({
    required this.label,
    required this.amount,
    required this.isPaid,
    this.methodLabel,
    this.pendingNote,
  });

  final String label;
  final double amount;
  final bool isPaid;
  final String? methodLabel;
  final String? pendingNote;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isPaid ? AppIcons.success : AppIcons.clock,
          size: 18.r,
          color: isPaid ? AppColors.success : AppColors.warning,
        ),
        Gap(AppSpacing.xs.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$label ${isPaid ? 'Paid' : 'Due'} — ${amount.toCurrencyDecimal}'
                '${methodLabel != null ? ' · $methodLabel' : ''}',
                style: AppTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isPaid ? null : AppColors.warning,
                ),
              ),
              if (pendingNote != null)
                Text(
                  pendingNote!,
                  style: AppTypography.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
