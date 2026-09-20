import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../../../config/env.dart';
import '../../../../core/design/design_system.dart';
import '../../../../core/extensions/extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../models/models.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../repositories/repositories.dart';
import '../../../checkout/presentation/controllers/razorpay_payment_controller.dart';
import '../../../wallet/presentation/providers/wallet_providers.dart';
import '../../../../core/network/friendly_error.dart';

/// Shown on the order-details page once an order reaches the delivery leg
/// with a balance still due. COD orders show an informational cash note
/// (the rider collects it, confirmed separately via `collectBalance` on
/// their side) — nothing to do in-app, so no sheet. Every other order shows
/// a "Pay Now" button opening a sheet with a plain-language price recap and
/// a live choice between Online (Razorpay) and the LNDRY wallet.
///
/// Deliberately does NOT offer "switch to Cash on Delivery" here even
/// though the order-details screen otherwise talks about COD: the rider's
/// collect-balance flow is gated server-side on the order's original
/// checkout-time choice (`orders.payment_method = 'COD'`), not on this
/// specific payment — offering a live switch here without also changing
/// that gate would silently fail to tell the rider to collect cash.
class BalancePaymentCard extends StatelessWidget {
  const BalancePaymentCard({super.key, required this.order, required this.onPaid});

  final OrderModel order;
  final VoidCallback onPaid;

  double get _balanceDue => (order.total - order.amountPaid).clamp(0, double.infinity);

  @override
  Widget build(BuildContext context) {
    final balance = _balanceDue;
    if (balance <= 0) return const SizedBox.shrink();

    final isCod = order.paymentMethod == PaymentMethod.cod;

    return AppCard.outlined(
      padding: EdgeInsets.all(AppSpacing.md.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.walletOutlined, color: AppColors.primary, size: 20.r),
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
              onPressed: () => _openPaySheet(context),
            ),
          ],
        ],
      ),
    );
  }

  void _openPaySheet(BuildContext context) {
    AppBottomSheet.show<void>(
      context: context,
      title: 'Pay Balance',
      isScrollControlled: true,
      child: _BalancePaySheetContent(order: order, balanceDue: _balanceDue, onPaid: onPaid),
    );
  }
}

/// The sheet's actual content — a separate widget (not an inline builder
/// closure) so its `ref.watch(walletProvider)` subscribes correctly; see
/// `feedback_riverpod_ref_watch_in_raw_builder` — a bare `ref.watch` inside
/// `showModalBottomSheet`'s own builder closure silently never rebuilds.
class _BalancePaySheetContent extends ConsumerStatefulWidget {
  const _BalancePaySheetContent({required this.order, required this.balanceDue, required this.onPaid});

  final OrderModel order;
  final double balanceDue;
  final VoidCallback onPaid;

  @override
  ConsumerState<_BalancePaySheetContent> createState() => _BalancePaySheetContentState();
}

class _BalancePaySheetContentState extends ConsumerState<_BalancePaySheetContent> {
  late final RazorpayPaymentController _paymentController;
  bool _isProcessing = false;
  String? _processingMethod;

  @override
  void initState() {
    super.initState();
    _paymentController = RazorpayPaymentController(
      onSuccess: _handleRazorpaySuccess,
      onFailure: _handleRazorpayFailure,
    );
  }

  @override
  void dispose() {
    _paymentController.dispose();
    super.dispose();
  }

  Future<void> _payOnline() async {
    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
      _processingMethod = 'online';
    });
    try {
      final repo = ref.read(customerRepositoryProvider);
      final paymentResult = await repo.createPaymentOrder(orderId: widget.order.id);

      final gatewayKey = paymentResult.keyId?.isNotEmpty == true ? paymentResult.keyId! : Env.razorpayKey;
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
        AppSnackBar.showError(context, 'Could not start payment: ${friendlyError(e)}');
      }
    }
  }

  Future<void> _handleRazorpaySuccess(PaymentSuccessResponse response) async {
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
      if (!verifyResult.success) {
        setState(() => _isProcessing = false);
        AppSnackBar.showError(context, 'Payment verification failed.');
        return;
      }
      _finishWithSuccess('Online Payment');
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

  void _handleRazorpayFailure(PaymentFailureResponse response) {
    if (!mounted) return;
    setState(() => _isProcessing = false);
    final isCancel = response.code == 2 || (response.message ?? '').toLowerCase().contains('cancel');
    AppSnackBar.showError(
      context,
      isCancel ? 'Payment cancelled. You can retry safely.' : 'Payment failed. Please try again.',
    );
  }

  Future<void> _payFromWallet(double walletBalance) async {
    if (_isProcessing) return;
    if (walletBalance < widget.balanceDue) {
      AppSnackBar.showError(
        context,
        'Your wallet balance (${walletBalance.toCurrencyDecimal}) is less than the amount due.',
      );
      return;
    }
    setState(() {
      _isProcessing = true;
      _processingMethod = 'wallet';
    });
    try {
      final result = await ref.read(customerRepositoryProvider).payWithWallet(orderId: widget.order.id);
      if (!mounted) return;
      if (!result.success) {
        setState(() => _isProcessing = false);
        AppSnackBar.showError(context, result.message ?? 'Payment from wallet failed.');
        return;
      }
      ref.invalidate(walletProvider);
      _finishWithSuccess('LNDRY Wallet');
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        AppSnackBar.showError(context, 'Could not pay from wallet: ${friendlyError(e)}');
      }
    }
  }

  void _finishWithSuccess(String methodLabel) {
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    AppSnackBar.showSuccess(context, 'Balance paid via $methodLabel!');
    widget.onPaid();
  }

  @override
  Widget build(BuildContext context) {
    final walletAsync = ref.watch(walletProvider);
    final walletBalance = walletAsync.value?.balance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Plain-language price recap ─────────────────────────────────
        AppCard.outlined(
          padding: EdgeInsets.all(AppSpacing.md.r),
          child: Column(
            children: [
              _PriceLine(label: 'Order Value', amount: widget.order.total),
              Gap(AppSpacing.xs.h),
              _PriceLine(label: 'Already Paid', amount: -widget.order.amountPaid, isSubtle: true),
              Gap(AppSpacing.sm.h),
              const Divider(height: 1),
              Gap(AppSpacing.sm.h),
              _PriceLine(label: 'Balance Due Now', amount: widget.balanceDue, isTotal: true),
            ],
          ),
        ),
        Gap(AppSpacing.md.h),
        Text(
          'Choose how you\'d like to pay',
          style: AppTypography.labelMedium.copyWith(color: AppColors.textSecondary),
        ),
        Gap(AppSpacing.cardGap.h),
        _PayMethodTile(
          icon: AppIcons.payment,
          label: 'Pay Online',
          subtitle: 'UPI, card, netbanking via Razorpay',
          isLoading: _isProcessing && _processingMethod == 'online',
          isDisabled: _isProcessing,
          onTap: _payOnline,
        ),
        Gap(AppSpacing.cardGap.h),
        walletAsync.when(
          data: (wallet) => _PayMethodTile(
            icon: AppIcons.wallet,
            label: 'Pay from LNDRY Wallet',
            subtitle: 'Balance: ${wallet.balance.toCurrencyDecimal}',
            isLoading: _isProcessing && _processingMethod == 'wallet',
            isDisabled: _isProcessing || wallet.balance < widget.balanceDue,
            onTap: () => _payFromWallet(wallet.balance),
          ),
          loading: () => _PayMethodTile(
            icon: AppIcons.wallet,
            label: 'Pay from LNDRY Wallet',
            subtitle: 'Checking your balance...',
            isLoading: false,
            isDisabled: true,
            onTap: () {},
          ),
          error: (_, __) => _PayMethodTile(
            icon: AppIcons.wallet,
            label: 'Pay from LNDRY Wallet',
            subtitle: 'Could not load your wallet balance',
            isLoading: false,
            isDisabled: true,
            onTap: () {},
          ),
        ),
        if (!_isProcessing && walletBalance != null && walletBalance < widget.balanceDue) ...[
          Gap(AppSpacing.xs.h),
          Text(
            'Not enough balance to cover this amount from your wallet alone.',
            style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }
}

class _PriceLine extends StatelessWidget {
  const _PriceLine({required this.label, required this.amount, this.isTotal = false, this.isSubtle = false});

  final String label;
  final double amount;
  final bool isTotal;
  final bool isSubtle;

  @override
  Widget build(BuildContext context) {
    final labelStyle = isTotal
        ? AppTypography.titleSmall.copyWith(fontWeight: FontWeight.bold)
        : AppTypography.bodyMedium.copyWith(color: isSubtle ? AppColors.textSecondary : null);
    final amountStyle = isTotal
        ? AppTypography.titleMedium.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)
        : AppTypography.bodyMedium.copyWith(color: isSubtle ? AppColors.textSecondary : null);
    final sign = amount < 0 ? '−' : '';
    return Row(
      children: [
        Text(label, style: labelStyle),
        const Spacer(),
        Text('$sign${amount.abs().toCurrencyDecimal}', style: amountStyle),
      ],
    );
  }
}

class _PayMethodTile extends StatelessWidget {
  const _PayMethodTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.isLoading,
    required this.isDisabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool isLoading;
  final bool isDisabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.lg.r),
      child: InkWell(
        onTap: isDisabled ? null : onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg.r),
        child: Container(
          padding: EdgeInsets.all(14.r),
          decoration: BoxDecoration(
            color: isDisabled ? AppColors.surfaceVariant.withValues(alpha: 0.4) : Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.lg.r),
            border: Border.all(color: AppColors.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 40.r,
                height: 40.r,
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.md.r),
                ),
                child: Icon(icon, color: AppColors.primary, size: 20.r),
              ),
              Gap(AppSpacing.sm.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.w700)),
                    Gap(2.h),
                    Text(subtitle, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ),
              if (isLoading)
                SizedBox(
                  width: 20.r,
                  height: 20.r,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(AppIcons.chevronRight, size: 18.r, color: AppColors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
