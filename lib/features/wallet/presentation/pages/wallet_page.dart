import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../../../config/env.dart';
import '../../../../core/design/design_system.dart';
import '../../../../core/extensions/extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../repositories/repositories.dart';
import '../../../checkout/presentation/controllers/razorpay_payment_controller.dart';
import '../providers/wallet_providers.dart';

/// "My Wallet" — balance, transaction history, and a way to add money.
/// Reachable from Profile → Account Details, alongside Coupons & Offers.
class WalletPage extends ConsumerStatefulWidget {
  const WalletPage({super.key});

  @override
  ConsumerState<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends ConsumerState<WalletPage> {
  late final RazorpayPaymentController _paymentController;
  bool _isToppingUp = false;

  @override
  void initState() {
    super.initState();
    _paymentController = RazorpayPaymentController(
      onSuccess: _handleTopUpSuccess,
      onFailure: _handleTopUpFailure,
    );
  }

  @override
  void dispose() {
    _paymentController.dispose();
    super.dispose();
  }

  Future<void> _startTopUp(double amount) async {
    setState(() => _isToppingUp = true);
    try {
      final repo = ref.read(customerRepositoryProvider);
      final order = await repo.createWalletTopUp(amount);
      if (order.razorpayOrderId.isEmpty) {
        throw Exception('Top-up could not be started.');
      }
      final user = ref.read(currentUserProvider);
      final amountPaise = (order.amount * 100).round();
      _paymentController.open(<String, dynamic>{
        'key': order.keyId?.isNotEmpty == true ? order.keyId : Env.razorpayKey,
        'order_id': order.razorpayOrderId,
        if (amountPaise > 0) 'amount': amountPaise,
        'currency': order.currency,
        'name': 'LNDRY Wallet Top-up',
        'description': 'Add money to your LNDRY wallet',
        'timeout': 300,
        'prefill': <String, dynamic>{
          if (user?.name.isNotEmpty == true) 'name': user!.name,
          if (user?.phone.isNotEmpty == true) 'contact': user!.phone,
          if (user?.email?.isNotEmpty == true) 'email': user!.email,
        },
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isToppingUp = false);
        AppSnackBar.showError(context, 'Could not start top-up: ${e.toString()}');
      }
    }
  }

  Future<void> _handleTopUpSuccess(PaymentSuccessResponse response) async {
    final orderId = response.orderId;
    final paymentId = response.paymentId;
    final signature = response.signature;
    if (orderId == null || paymentId == null || signature == null) {
      if (mounted) {
        setState(() => _isToppingUp = false);
        AppSnackBar.showError(context, 'Payment response was incomplete.');
      }
      return;
    }

    try {
      final repo = ref.read(customerRepositoryProvider);
      await repo.verifyWalletTopUp(
        paymentId: paymentId,
        orderId: orderId,
        signature: signature,
      );
      ref.invalidate(walletProvider);
      ref.invalidate(walletTransactionsProvider);
      if (mounted) {
        setState(() => _isToppingUp = false);
        AppSnackBar.showSuccess(context, 'Money added to your wallet!');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isToppingUp = false);
        AppSnackBar.showError(context, 'Top-up verification failed: ${e.toString()}');
      }
    }
  }

  void _handleTopUpFailure(PaymentFailureResponse response) {
    if (!mounted) return;
    setState(() => _isToppingUp = false);
    final isCancel = response.code == 2 ||
        (response.message ?? '').toLowerCase().contains('cancel');
    AppSnackBar.showError(
      context,
      isCancel ? 'Top-up cancelled.' : 'Top-up failed. Please try again.',
    );
  }

  Future<void> _showAddMoneySheet() async {
    final controller = TextEditingController();
    final amount = await AppBottomSheet.show<double>(
      context: context,
      title: 'Add Money to Wallet',
      isScrollControlled: true,
      child: Padding(
        padding: EdgeInsets.only(bottom: AppSpacing.md.h),
        child: AppTextField(
          controller: controller,
          label: 'Amount (₹10 - ₹10,000)',
          keyboardType: TextInputType.number,
          autofocus: true,
        ),
      ),
      primaryActionLabel: 'Proceed to Pay',
      onPrimaryAction: () {
        final value = double.tryParse(controller.text.trim());
        Navigator.of(context).pop(value);
      },
    );

    if (amount == null || amount < 10 || amount > 10000) {
      if (amount != null && mounted) {
        AppSnackBar.showError(context, 'Enter an amount between ₹10 and ₹10,000.');
      }
      return;
    }
    await _startTopUp(amount);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final isDark = theme.brightness == Brightness.dark;
    final walletAsync = ref.watch(walletProvider);
    final transactionsAsync = ref.watch(walletTransactionsProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('My Wallet', style: AppTypography.titleLarge),
        centerTitle: true,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.surface,
        elevation: 0,
      ),
      body: _isToppingUp
          ? const AppLoadingPage(message: 'Securing transaction with Razorpay...')
          : SafeArea(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(walletProvider);
                  ref.invalidate(walletTransactionsProvider);
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.all(AppSpacing.pagePaddingH.w),
                  children: [
                    walletAsync.when(
                      data: (wallet) => _WalletBalanceCard(
                        balance: wallet.balance,
                        onAddMoney: _showAddMoneySheet,
                      ),
                      loading: () => const _WalletBalanceCard(
                        balance: null,
                        onAddMoney: null,
                      ),
                      error: (_, __) => AppErrorWidget(
                        message: "Couldn't load your wallet balance.",
                        onRetry: () => ref.invalidate(walletProvider),
                      ),
                    ),
                    Gap(AppSpacing.sectionGap.h),
                    Text('Transaction History', style: AppTypography.titleMedium),
                    Gap(AppSpacing.cardGap.h),
                    transactionsAsync.when(
                      data: (transactions) => transactions.isEmpty
                          ? const AppEmptyState(
                              icon: AppIcons.walletOutlined,
                              title: 'No transactions yet',
                              subtitle:
                                  'Money you add or earn will show up here.',
                            )
                          : Column(
                              children: transactions
                                  .map((t) => Padding(
                                        padding: EdgeInsets.only(
                                            bottom: AppSpacing.sm.h),
                                        child: _WalletTransactionTile(
                                            transaction: t),
                                      ))
                                  .toList(),
                            ),
                      loading: () => Padding(
                        padding: EdgeInsets.symmetric(
                            vertical: AppSpacing.xxl.h),
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                      error: (_, __) => AppErrorWidget(
                        message: "Couldn't load transaction history.",
                        onRetry: () => ref.invalidate(walletTransactionsProvider),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _WalletBalanceCard extends StatelessWidget {
  const _WalletBalanceCard({required this.balance, required this.onAddMoney});

  final double? balance;
  final VoidCallback? onAddMoney;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppSpacing.cardPadding.w * 1.25),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(AppRadius.card.r),
        boxShadow: AppElevation.medium,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Wallet Balance',
            style: AppTypography.labelMedium.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          Gap(6.h),
          balance == null
              ? SizedBox(
                  height: 34.h,
                  width: 90.w,
                  child: const LinearProgressIndicator(color: Colors.white24),
                )
              : Text(
                  '₹${balance!.toStringAsFixed(2)}',
                  style: AppTypography.headlineLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
          Gap(AppSpacing.md.h),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onAddMoney,
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.15),
                side: const BorderSide(color: Colors.white54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button.r),
                ),
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm.h),
              ),
              child: Text(
                'Add Money',
                style: AppTypography.labelLarge.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletTransactionTile extends StatelessWidget {
  const _WalletTransactionTile({required this.transaction});

  final WalletTransactionModel transaction;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final isCredit = transaction.isCredit;
    final amountColor = isCredit ? AppColors.success : AppColors.error;

    return AppCard.outlined(
      backgroundColor: isDark ? AppColors.darkSurfaceContainer : AppColors.surface,
      child: Row(
        children: [
          Container(
            width: 40.r,
            height: 40.r,
            decoration: BoxDecoration(
              color: (isCredit ? AppColors.success : AppColors.error)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.md.r),
            ),
            child: Icon(
              isCredit
                  ? Icons.add_circle_outline_rounded
                  : Icons.remove_circle_outline_rounded,
              color: amountColor,
              size: 20.r,
            ),
          ),
          Gap(AppSpacing.cardGap.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.description,
                  style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Gap(2.h),
                Text(
                  transaction.createdAt.toDayDate,
                  style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            '${isCredit ? '+' : '-'}₹${transaction.amount.toStringAsFixed(2)}',
            style: AppTypography.titleSmall.copyWith(
              fontWeight: FontWeight.bold,
              color: amountColor,
            ),
          ),
        ],
      ),
    );
  }
}
