import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design/design_system.dart';
import '../../../../core/extensions/extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../models/models.dart';
import '../../../../repositories/repositories.dart';
import '../../../../shared/repositories/base_repository.dart';

/// Shows the customer's most recently delivered order alongside the review
/// they left for it (if any). Only the customer's own name is ever shown
/// here — never a phone number, since this is reachable from the home
/// screen's top bar rather than a private order-management context.
class LastOrderReviewPage extends ConsumerStatefulWidget {
  const LastOrderReviewPage({super.key});

  @override
  ConsumerState<LastOrderReviewPage> createState() =>
      _LastOrderReviewPageState();
}

class _LastOrderReviewPageState extends ConsumerState<LastOrderReviewPage> {
  bool _isLoading = true;
  OrderModel? _lastOrder;
  ReviewModel? _review;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final repo = ref.read(customerRepositoryProvider);
    try {
      final ordersRes = await repo.getMyOrders(
        params: const PaginationParams(pageSize: 20),
      );
      final delivered = ordersRes.items
          .where((o) =>
              o.status == OrderStatus.delivered ||
              o.status == OrderStatus.deliveryOtpVerified)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final lastOrder = delivered.isNotEmpty ? delivered.first : null;

      ReviewModel? review;
      if (lastOrder != null) {
        final reviewsRes = await repo.getMyReviews(
          params: const PaginationParams(pageSize: 50),
        );
        for (final r in reviewsRes.items) {
          if (r.orderId == lastOrder.id) {
            review = r;
            break;
          }
        }
      }

      if (mounted) {
        setState(() {
          _lastOrder = lastOrder;
          _review = review;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final isDark = theme.brightness == Brightness.dark;
    final order = _lastOrder;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Last Order & Review', style: AppTypography.titleLarge),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(AppIcons.back),
          onPressed: () => context.pop(),
        ),
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.surface,
        elevation: 0,
      ),
      body: SafeArea(
        child: _isLoading
            ? const AppLoadingPage(message: 'Loading...')
            : order == null
                ? const AppEmptyState(
                    icon: Icons.local_laundry_service_outlined,
                    title: 'No Delivered Orders Yet',
                    subtitle:
                        'Your most recent completed order will show up here.',
                  )
                : SingleChildScrollView(
                    padding: EdgeInsets.all(AppSpacing.pagePaddingH.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppCard.outlined(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Order #${order.orderNumber.isNotEmpty ? order.orderNumber : order.id.toUpperCase()}',
                                style: AppTypography.labelLarge,
                              ),
                              Gap(AppSpacing.sm.h),
                              Text(
                                order.items.isNotEmpty
                                    ? order.items.first.serviceName
                                    : 'Laundry service',
                                style: AppTypography.bodyMedium,
                              ),
                              Gap(AppSpacing.sm.h),
                              Text(
                                order.createdAt.toDateString,
                                style: AppTypography.caption,
                              ),
                            ],
                          ),
                        ),
                        Gap(AppSpacing.sectionGap.h),
                        Text('Your Review', style: AppTypography.titleMedium),
                        Gap(AppSpacing.cardGap.h),
                        if (_review == null)
                          AppCard.outlined(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "You haven't reviewed this order yet.",
                                  style: AppTypography.bodyMedium,
                                ),
                                Gap(AppSpacing.cardGap.h),
                                AppButton.outlined(
                                  label: 'Write a Review',
                                  onPressed: () => context.push(
                                    '${AppRoutes.orders}/details/${order.id}',
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          AppCard.outlined(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _ratingRow('Vendor rating', _review!.vendorRating),
                                if (_review!.riderRating != null) ...[
                                  Gap(AppSpacing.sm.h),
                                  _ratingRow(
                                      'Delivery rating', _review!.riderRating!),
                                ],
                                if (_review!.comment != null &&
                                    _review!.comment!.isNotEmpty) ...[
                                  Gap(AppSpacing.cardGap.h),
                                  Text(_review!.comment!,
                                      style: AppTypography.bodySmall),
                                ],
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _ratingRow(String label, int rating) {
    final percent = (rating / 5 * 100).round();
    return Row(
      children: [
        Expanded(child: Text(label, style: AppTypography.bodyMedium)),
        Row(
          children: List.generate(
            5,
            (i) => Icon(
              i < rating ? Icons.star_rounded : Icons.star_border_rounded,
              color: AppColors.warning,
              size: 16,
            ),
          ),
        ),
        Gap(AppSpacing.sm.w),
        Text('$percent%',
            style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }
}
