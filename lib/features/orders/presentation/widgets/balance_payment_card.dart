import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../../../config/env.dart';
import '../../../../core/design/design_system.dart';
import '../../../../core/extensions/extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../models/models.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../repositories/repositories.dart';
import '../../../checkout/presentation/controllers/razorpay_payment_controller.dart';

/// Shown on the order-details page once an order reaches the delivery leg
/// with a balance still due. COD orders show an informational cash note
/// (the rider collects it, confirmed separately via `collectBalance` on
/// their side); ONLINE orders show a "Pay Now" button that reuses the same
/// [RazorpayPaymentController] the checkout advance payment uses.
class BalancePaymentCard extends ConsumerStatefulWidget {
  const BalancePaymentCard({super.key, required this.order, required this.onPaid});

  final OrderModel order;
  final VoidCallback onPaid;

  @override
  ConsumerState<BalancePaymentCard> createState() => _BalancePaymentCardState();
}

class _BalancePaymentCardState extends ConsumerState<BalancePaymentCard> {
  late final RazorpayPaymentController _paymentController;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _paymentController = RazorpayPaymentController(
      onSuccess: _handleSuccess,
      onFailure: _handleFailure,
    );
  }

  @override
  void dispose() {
    _paymentController.dispose();
    super.dispose();
  }

  double get _balanceDue => (widget.order.total - widget.order.amountPaid).clamp(0, double.infinity);

  Future<void> _payNow() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final repo = ref.read(customerRepositoryProvider);
      final paymentResult = await repo.createPaymentOrder(orderId: widget.order.id);

      final gatewayKey = paymentResult.keyId?.isNotEmpty == true
          ? paymentResult.keyId!
          : Env.razorpayKey;
      if (gatewayKey.isEmpty || paymentResult.razorpayOrderId.isEmpty) {
        if (mounted) {
          setState(() => _isProcessing = false);
          AppSnackBar.showError(context, 'Payment is unavailable right now. Please try again shortly.');
        }
        return;
      }

      final user = ref.read(currentUserProvider);
      final amountPaise = paymentResult.amount > 0 ? (paymentResult.amount * 100).round() : 0;

      _paymentController.open(<String, dynamic>{
        'key': gatewayKey,
        'order_id': paymentResult.razorpayOrderId,
        if (amountPaise > 0) 'amount': amountPaise,
        'currency': paymentResult.currency,
        'name': 'LNDRY',
        'description': 'Balance payment for order #${widget.order.orderNumber}',
        'timeout': 300,
        'prefill': <String, dynamic>{
          if (user?.name.isNotEmpty == true) 'name': user!.name,
          if (user?.phone.isNotEmpty == true) 'contact': user!.phone,
          if (user?.email?.isNotEmpty == true) 'email': user!.email,
        },
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        AppSnackBar.showError(context, 'Could not start payment: ${e.toString()}');
      }
    }
  }

  Future<void> _handleSuccess(PaymentSuccessResponse response) async {
    final razorpayOrderId = response.orderId;
    final razorpayPaymentId = response.paymentId;
    final razorpaySignature = response.signature;
    if (razorpayOrderId == null ||
        razorpayOrderId.isEmpty ||
        razorpayPaymentId == null ||
        razorpayPaymentId.isEmpty ||
        razorpaySignature == null ||
        razorpaySignature.isEmpty) {
      if (mounted) {
        setState(() => _isProcessing = false);
        AppSnackBar.showError(context, 'Payment response was incomplete. Please contact support.');
      }
      return;
    }

    try {
      final verifyResult = await ref.read(customerRepositoryProvider).verifyPayment(
            razorpayOrderId: razorpayOrderId,
            razorpayPaymentId: razorpayPaymentId,
            razorpaySignature: razorpaySignature,
          );
      if (!mounted) return;
      setState(() => _isProcessing = false);
      if (!verifyResult.success) {
        AppSnackBar.showError(context, 'Payment verification failed.');
        return;
      }
      AppSnackBar.showSuccess(context, 'Balance paid successfully!');
      widget.onPaid();
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        AppSnackBar.showError(
          context,
          'Payment captured, but verification failed. Please contact support if the balance still shows as due.',
        );
      }
    }
  }

  void _handleFailure(PaymentFailureResponse response) {
    if (!mounted) return;
    setState(() => _isProcessing = false);
    final isCancel = response.code == 2 || (response.message ?? '').toLowerCase().contains('cancel');
    AppSnackBar.showError(
      context,
      isCancel ? 'Payment cancelled. You can retry safely.' : 'Payment failed. Please try again.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final balance = _balanceDue;
    if (balance <= 0) return const SizedBox.shrink();

    final isCod = widget.order.paymentMethod == PaymentMethod.cod;

    return AppCard.outlined(
      padding: EdgeInsets.all(AppSpacing.md.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined, color: AppColors.primary, size: 20.r),
              Gap(AppSpacing.cardGap.h),
              Text('Balance Due', style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              Text(
                balance.toCurrencyDecimal,
                style: AppTypography.titleMedium.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Gap(AppSpacing.cardGap.h),
          if (isCod)
            Text(
              'Pay this in cash to your delivery partner when your order arrives.',
              style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
            )
          else ...[
            Text(
              'Pay now to avoid any delay at delivery.',
              style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
            ),
            Gap(AppSpacing.cardGap.h),
            AppButton(
              label: 'Pay ${balance.toCurrencyDecimal} Now',
              isLoading: _isProcessing,
              isDisabled: _isProcessing,
              onPressed: _payNow,
            ),
          ],
        ],
      ),
    );
  }
}
