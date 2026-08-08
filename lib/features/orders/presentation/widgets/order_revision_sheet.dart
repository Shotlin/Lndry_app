import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';

import '../../../../core/design/design_system.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../models/models.dart';

enum ReconciliationDecision { accept, reject }

/// Display suffix for a reconciliation line-change's unit, e.g. " kg" / " sq ft".
String _unitSuffix(String? unit) {
  final u = unit?.toLowerCase();
  if (u == 'kg') return ' kg';
  if (u == 'sqft') return ' sq ft';
  return '';
}

/// Shown when an order's status is `RECONCILIATION_PENDING` — the vendor's
/// authoritative recount differs from the rider's earlier correction, and
/// the customer must explicitly accept or reject the new total before
/// processing continues. Built on [AppBottomSheet]'s two-button form
/// (primary/secondary action), used here for the first time as an actual
/// accept/reject choice rather than a single confirm action.
class OrderRevisionSheet {
  OrderRevisionSheet._();

  static Future<ReconciliationDecision?> show({
    required BuildContext context,
    required OrderReconciliationModel reconciliation,
  }) {
    return AppBottomSheet.show<ReconciliationDecision>(
      context: context,
      title: 'Your Order Total Was Updated',
      isScrollControlled: true,
      primaryActionLabel: 'Accept New Total',
      onPrimaryAction: () =>
          Navigator.of(context).pop(ReconciliationDecision.accept),
      secondaryActionLabel: 'Reject',
      onSecondaryAction: () =>
          Navigator.of(context).pop(ReconciliationDecision.reject),
      child: _RevisionContent(reconciliation: reconciliation),
    );
  }
}

class _RevisionContent extends StatelessWidget {
  const _RevisionContent({required this.reconciliation});

  final OrderReconciliationModel reconciliation;

  @override
  Widget build(BuildContext context) {
    final previousTotal = reconciliation.previousPayableAmountPaise / 100.0;
    final proposedTotal = reconciliation.proposedPayableAmountPaise / 100.0;
    final delta = proposedTotal - previousTotal;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'The vendor re-weighed/recounted your items and found a difference. '
          'Review the evidence below before deciding.',
          style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
        ),
        Gap(AppSpacing.md.h),

        if (reconciliation.photos.isNotEmpty) ...[
          SizedBox(
            height: 84.r,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: reconciliation.photos.length,
              separatorBuilder: (_, __) => Gap(8.w),
              itemBuilder: (context, idx) => ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm.r),
                child: Image.network(
                  reconciliation.photos[idx],
                  width: 84.r,
                  height: 84.r,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          Gap(AppSpacing.md.h),
        ],

        AppCard.outlined(
          padding: EdgeInsets.all(AppSpacing.md.r),
          child: Column(
            children: [
              _totalRow('Previous total', previousTotal, isBold: false),
              Gap(6.h),
              _totalRow('New total', proposedTotal, isBold: true, color: AppColors.primary),
              const Divider(),
              _totalRow(
                delta >= 0 ? 'Increase' : 'Decrease',
                delta.abs(),
                isBold: true,
                color: delta >= 0 ? AppColors.error : AppColors.success,
              ),
            ],
          ),
        ),

        if (reconciliation.lineChanges.isNotEmpty) ...[
          Gap(AppSpacing.md.h),
          Text('What changed', style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.bold)),
          Gap(8.h),
          ...reconciliation.lineChanges.map((c) => Padding(
                padding: EdgeInsets.symmetric(vertical: 4.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (c.isNew)
                      Text(
                        'New service added',
                        style: AppTypography.bodyMedium.copyWith(color: AppColors.success, fontWeight: FontWeight.bold),
                      )
                    else if (c.isReclassified)
                      Text(
                        'Moved: ${c.previousName ?? 'Item'} → ${c.proposedName ?? 'Item'}',
                        style: AppTypography.bodyMedium.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            (c.isReclassified || c.isNew) ? (c.proposedName ?? 'Item') : (c.previousName ?? 'Item'),
                            style: AppTypography.bodyMedium,
                          ),
                        ),
                        Text(
                          c.isNew
                              ? '${c.proposedQuantity}${_unitSuffix(c.proposedUnit)}'
                              : '${c.previousQuantity}${_unitSuffix(c.previousUnit)} → ${c.proposedQuantity}${_unitSuffix(c.proposedUnit)}',
                          style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
              )),
        ],

        if (reconciliation.reason != null && reconciliation.reason!.isNotEmpty) ...[
          Gap(AppSpacing.md.h),
          Text('Vendor note', style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.bold)),
          Gap(4.h),
          Text(reconciliation.reason!, style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
        ],
      ],
    );
  }

  Widget _totalRow(String label, double amount, {required bool isBold, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTypography.bodyMedium.copyWith(color: color)),
        Text(
          CurrencyUtils.formatDecimal(amount),
          style: AppTypography.bodyLarge.copyWith(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: color,
          ),
        ),
      ],
    );
  }
}
