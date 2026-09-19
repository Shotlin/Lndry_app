import '../../../../core/design/design_system.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../core/extensions/extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../repositories/repositories.dart';

class OrderConfirmationPage extends ConsumerStatefulWidget {
  const OrderConfirmationPage({
    super.key,
    required this.orderId,
    this.orderNumber,
  });
  final String orderId;

  /// The customer-facing order number (e.g. LNDR-20260919-43T) returned when
  /// the order was placed. Falls back to fetching it by [orderId] if absent.
  final String? orderNumber;

  @override
  ConsumerState<OrderConfirmationPage> createState() =>
      _OrderConfirmationPageState();
}

class _OrderConfirmationPageState extends ConsumerState<OrderConfirmationPage> {
  String? _orderNumber;

  String get orderId => widget.orderId;

  /// The same customer-facing order number the Order Details screen shows.
  /// Only if it genuinely can't be resolved does this fall back to the short
  /// internal-id suffix.
  String get _displayId {
    final number = _orderNumber;
    if (number != null && number.isNotEmpty) return number;
    if (orderId.isEmpty) return 'NEW';
    return orderId.length > 8
        ? orderId.substring(orderId.length - 8).toUpperCase()
        : orderId.toUpperCase();
  }

  @override
  void initState() {
    super.initState();
    final passed = widget.orderNumber;
    if (passed != null && passed.isNotEmpty) {
      _orderNumber = passed;
    } else if (orderId.isNotEmpty) {
      _loadOrderNumber();
    }
  }

  Future<void> _loadOrderNumber() async {
    try {
      final order =
          await ref.read(customerRepositoryProvider).getOrderById(orderId);
      if (mounted && order.orderNumber.isNotEmpty) {
        setState(() => _orderNumber = order.orderNumber);
      }
    } catch (_) {
      // Keep the short-id fallback rather than blocking the success screen.
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        context.go(AppRoutes.home);
      },
      child: Scaffold(
        backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.pagePaddingH.w,
              vertical: AppSpacing.pagePaddingV.h * 2,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),

                // Success icon
                Center(
                  child: Container(
                    width: 140.r,
                    height: 140.r,
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(AppIcons.success,
                        size: 80.r, color: AppColors.success),
                  ),
                ),
                const Gap(32),

                Text(
                  'Payment Successful!',
                  style: AppTypography.headlineLarge,
                  textAlign: TextAlign.center,
                ),
                const Gap(16),

                // Spec §12 exact confirmation copy
                Text(
                  'Your payment has been verified and the order has been sent to '
                  'the selected laundry partner.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.onSurfaceVariant,
                    height: 1.6,
                  ),
                  textAlign: TextAlign.center,
                ),
                const Gap(24),

                // Status card
                AppCard.outlined(
                  backgroundColor: isDark
                      ? AppColors.darkSurfaceContainer
                      : AppColors.primaryContainer.withOpacity(0.4),
                  borderColor: AppColors.primary.withOpacity(0.3),
                  padding: EdgeInsets.all(AppSpacing.md.r),
                  child: Column(
                    children: [
                      // Canonical status label per spec §12
                      Center(
                        child: Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 14.w, vertical: 7.h),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(AppRadius.full.r),
                          ),
                          child: Text(
                            'Waiting for Vendor Confirmation',
                            style: AppTypography.labelMedium.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const Gap(16),
                      _Row(label: 'Order ID', value: '#$_displayId'),
                      const Gap(8),
                      _Row(
                        label: 'Next step',
                        value:
                            'You will be notified when the vendor accepts or rejects.',
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                AppButton(
                  label: 'Track Order',
                  onPressed: () {
                    if (orderId.isNotEmpty) {
                      context.go('/orders/details/$orderId');
                    } else {
                      context.go(AppRoutes.orders);
                    }
                  },
                ),
                const Gap(16),
                AppButton.text(
                  label: 'Back to Home',
                  onPressed: () => context.go(AppRoutes.home),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ',
          style: AppTypography.bodySmall
              .copyWith(color: AppColors.onSurfaceVariant),
        ),
        Expanded(
          child: Text(
            value,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textBlack,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
