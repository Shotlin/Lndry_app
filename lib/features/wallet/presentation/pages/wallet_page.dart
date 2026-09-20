import 'dart:async';

import 'package:google_fonts/google_fonts.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../../../config/env.dart';
import '../../../../core/constants/asset_constants.dart';
import '../../../../core/design/design_system.dart';
import '../../../../core/design/premium_type.dart';
import '../../../../core/extensions/extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../repositories/repositories.dart';
import '../../../checkout/presentation/controllers/razorpay_payment_controller.dart';
import '../providers/wallet_providers.dart';
import '../../../../core/network/friendly_error.dart';

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
        AppSnackBar.showError(
            context, 'Could not start top-up: ${friendlyError(e)}');
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
        AppSnackBar.showError(
            context, 'Top-up verification failed: ${friendlyError(e)}');
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

  Future<void> _showAddMoneySheet({double? initialAmount}) async {
    final amount = await showModalBottomSheet<double>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor:
          context.isDark ? AppColors.darkSurfaceContainer : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.sheet.r)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: _AddMoneySheetContent(initialAmount: initialAmount),
      ),
    );

    if (amount == null) return;
    await _startTopUp(amount);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final isDark = theme.brightness == Brightness.dark;
    final walletAsync = ref.watch(walletProvider);
    final transactionsAsync = ref.watch(walletTransactionsProvider);
    final hasTransactions = transactionsAsync.valueOrNull?.isNotEmpty ?? false;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('My Wallet', style: premiumFont(19, weight: FontWeight.w800)),
        centerTitle: true,
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.surface,
        elevation: 0,
        actions: [
          Padding(
            padding: EdgeInsets.only(right: AppSpacing.pagePaddingH.w),
            child: Image.asset(AssetConstants.logoWordmark, height: 24.h),
          ),
        ],
      ),
      body: _isToppingUp
          ? const AppLoadingPage(
              message: 'Securing transaction with Razorpay...')
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
                    const _PendingWalletRedemptionBanner(),
                    walletAsync.when(
                      data: (wallet) => _WalletHeroCard(
                        balance: wallet.balance,
                        onAddMoney: () => _showAddMoneySheet(),
                      ),
                      loading: () => const _WalletHeroCard(
                        balance: null,
                        onAddMoney: null,
                      ),
                      error: (_, __) => AppErrorWidget(
                        message: "Couldn't load your wallet balance.",
                        onRetry: () => ref.invalidate(walletProvider),
                      ),
                    ),
                    Gap(18.h),
                    _QuickAmountRow(
                      onAmountSelected: (amt) =>
                          _showAddMoneySheet(initialAmount: amt),
                      onCustom: () => _showAddMoneySheet(),
                    ),
                    Gap(18.h),
                    const _WalletBenefitsRow(),
                    Gap(AppSpacing.sectionGap.h),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Transaction History',
                            style: premiumFont(16, weight: FontWeight.w700)),
                        if (hasTransactions)
                          Text(
                            'See all',
                            style: premiumFont(13,
                                weight: FontWeight.w700,
                                color: AppColors.primary),
                          ),
                      ],
                    ),
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
                        padding:
                            EdgeInsets.symmetric(vertical: AppSpacing.xxl.h),
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                      error: (_, __) => AppErrorWidget(
                        message: "Couldn't load transaction history.",
                        onRetry: () =>
                            ref.invalidate(walletTransactionsProvider),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// The gradient hero card — background art is [AssetConstants.walletHeroBg]
/// (the user-supplied "For Cleaner Days" wallet illustration), with the live
/// balance, tagline and Add Money CTA laid out over it as fractions of the
/// card's own rendered height/width so they line up with the art's empty
/// space at any screen size.
class _WalletHeroCard extends StatelessWidget {
  const _WalletHeroCard({required this.balance, required this.onAddMoney});

  final double? balance;
  final VoidCallback? onAddMoney;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 5 / 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xxl.r),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.primaryDark,
                AppColors.primary,
                AppColors.aqua
              ],
              stops: [0.0, 0.55, 1.0],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: AppElevation.medium,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final h = constraints.maxHeight;
              final w = constraints.maxWidth;
              return Stack(
                children: [
                  Positioned(
                      top: -h * 0.25, left: -w * 0.12, child: _blob(h * 0.85)),
                  Positioned(
                      bottom: -h * 0.35,
                      left: w * 0.22,
                      child: _blob(h * 1.05)),
                  Positioned(
                    right: w * 0.05,
                    top: h * 0.07,
                    width: w * 0.26,
                    child: Image.asset(AssetConstants.walletCoinBadge,
                        fit: BoxFit.contain),
                  ),
                  Positioned(
                    right: w * 0.09,
                    top: h * 0.42,
                    child: Text(
                      'For Cleaner\nDays',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.caveat(
                        fontSize: (h * 0.105).clamp(16, 22),
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        height: 1.05,
                      ),
                    ),
                  ),
                  Positioned(
                    left: w * 0.075,
                    bottom: h * 0.055,
                    child: Row(
                      children: [
                        Text(
                          'LNDRY WALLET',
                          style: premiumFont(
                            (h * 0.036).clamp(8, 10.5),
                            weight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.7),
                            letterSpacing: 1.2,
                          ),
                        ),
                        Gap(6.w),
                        Container(
                            width: 26,
                            height: 1,
                            color: Colors.white.withValues(alpha: 0.5)),
                      ],
                    ),
                  ),
                  Positioned(
                    right: w * 0.075,
                    bottom: h * 0.05,
                    child: Text(
                      'CLEANER DAYS\nBRIGHTER TOMORROWS',
                      textAlign: TextAlign.right,
                      style: premiumFont(
                        (h * 0.032).clamp(7, 9),
                        weight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.65),
                        letterSpacing: 1.0,
                        height: 1.5,
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                        w * 0.075, h * 0.09, w * 0.075, h * 0.16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'WALLET BALANCE',
                          style: premiumFont(
                            (h * 0.05).clamp(10, 13),
                            weight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.85),
                            letterSpacing: 1.4,
                          ),
                        ),
                        SizedBox(height: h * 0.014),
                        balance == null
                            ? SizedBox(
                                height: (h * 0.18).clamp(26, 40),
                                width: 90.w,
                                child: const LinearProgressIndicator(
                                    color: Colors.white24),
                              )
                            : Text(
                                '₹${balance!.toStringAsFixed(2)}',
                                style: premiumFont(
                                  (h * 0.18).clamp(26, 40),
                                  weight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                        SizedBox(height: h * 0.024),
                        Text(
                          'Fast. Secure. Ready for laundry.',
                          style: premiumFont(
                            (h * 0.055).clamp(11, 14),
                            weight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                        const Spacer(),
                        _HeroAddMoneyButton(
                            height: (h * 0.2).clamp(44, 56), onTap: onAddMoney),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _blob(double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.08),
        ),
      );
}

class _HeroAddMoneyButton extends StatelessWidget {
  const _HeroAddMoneyButton({required this.height, required this.onTap});

  final double height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.button.r),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.button.r),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.md.w),
            child: Row(
              children: [
                Container(
                  width: 26.r,
                  height: 26.r,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child:
                      Icon(Icons.add_rounded, color: Colors.white, size: 16.r),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      'Add Money',
                      style: premiumFont(15,
                          weight: FontWeight.w700, color: AppColors.primary),
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: AppColors.primary, size: 22.r),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickAmountRow extends StatelessWidget {
  const _QuickAmountRow(
      {required this.onAmountSelected, required this.onCustom});

  final ValueChanged<double> onAmountSelected;
  final VoidCallback onCustom;

  static const _presets = <double>[100, 250, 500];

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      for (final amt in _presets)
        _AmountPillChip(
          label: '₹${amt.toInt()}',
          onTap: () => onAmountSelected(amt),
        ),
      _AmountPillChip(
        label: 'Custom',
        icon: Icons.edit_rounded,
        outlined: true,
        onTap: onCustom,
      ),
    ];

    return Row(
      children: [
        for (var i = 0; i < chips.length; i++) ...[
          Expanded(child: chips[i]),
          if (i != chips.length - 1) Gap(10.w),
        ],
      ],
    );
  }
}

class _AmountPillChip extends StatelessWidget {
  const _AmountPillChip({
    required this.label,
    required this.onTap,
    this.icon,
    this.outlined = false,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return Material(
      color: outlined
          ? Colors.transparent
          : (isDark
              ? AppColors.darkSurfaceContainerHigh
              : AppColors.offerLavender),
      borderRadius: BorderRadius.circular(AppRadius.button.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.button.r),
        onTap: onTap,
        child: Container(
          height: 44.h,
          alignment: Alignment.center,
          decoration: outlined
              ? BoxDecoration(
                  border: Border.all(
                    color: isDark
                        ? AppColors.darkOutlineVariant
                        : AppColors.outlineVariant,
                    style: BorderStyle.solid,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.button.r),
                )
              : null,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15.r, color: AppColors.primary),
                Gap(6.w),
              ],
              Text(
                label,
                style:
                    premiumFont(13, weight: FontWeight.w700, color: AppColors.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WalletBenefitsRow extends StatelessWidget {
  const _WalletBenefitsRow();

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return Container(
      padding: EdgeInsets.symmetric(
          vertical: AppSpacing.md.h, horizontal: AppSpacing.sm.w),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceContainer : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg.r),
        border: Border.all(
          color:
              isDark ? AppColors.darkOutlineVariant : AppColors.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _BenefitItem(
              icon: Image.asset(AssetConstants.walletSecureIcon,
                  width: 40.r, height: 40.r),
              title: 'Secure\nwallet',
              subtitle: 'Your money\nstays safe',
            ),
          ),
          _divider(isDark),
          Expanded(
            child: _BenefitItem(
              icon: Image.asset(AssetConstants.walletInstantIcon,
                  width: 40.r, height: 40.r),
              title: 'Instant\ntop-up',
              subtitle: 'Get started\nin seconds',
            ),
          ),
          _divider(isDark),
          Expanded(
            child: _BenefitItem(
              icon: Container(
                width: 40.r,
                height: 40.r,
                decoration: const BoxDecoration(
                  color: AppColors.offerLavender,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.card_giftcard_rounded,
                    color: AppColors.primary, size: 20.r),
              ),
              title: 'Rewards\nready',
              subtitle: 'Earn while\nyou wash',
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(bool isDark) => Container(
        width: 1,
        height: 52.h,
        color: isDark ? AppColors.darkOutlineVariant : AppColors.outlineVariant,
      );
}

class _BenefitItem extends StatelessWidget {
  const _BenefitItem(
      {required this.icon, required this.title, required this.subtitle});

  final Widget icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        Gap(8.h),
        Text(
          title,
          textAlign: TextAlign.center,
          style: premiumFont(12, weight: FontWeight.w700, height: 1.2),
        ),
        Gap(2.h),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: premiumFont(10.5,
              weight: FontWeight.w400,
              height: 1.25,
              color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

/// Shows a vendor's pending in-person wallet redemption at the very top of
/// My Wallet — the customer reads the code aloud to confirm it themselves.
/// Renders nothing when there's no pending request (the common case).
class _PendingWalletRedemptionBanner extends ConsumerStatefulWidget {
  const _PendingWalletRedemptionBanner();

  @override
  ConsumerState<_PendingWalletRedemptionBanner> createState() =>
      _PendingWalletRedemptionBannerState();
}

class _PendingWalletRedemptionBannerState
    extends ConsumerState<_PendingWalletRedemptionBanner> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pendingAsync = ref.watch(pendingWalletRedemptionProvider);
    return pendingAsync.when(
      data: (pending) {
        if (pending == null || pending.isExpired) {
          return const SizedBox.shrink();
        }
        final remaining = pending.expiresAt.difference(DateTime.now());
        final minutes = remaining.inMinutes.clamp(0, 99);
        final seconds = (remaining.inSeconds % 60).clamp(0, 59);
        return Container(
          width: double.infinity,
          margin: EdgeInsets.only(bottom: AppSpacing.sectionGap.h),
          padding: EdgeInsets.all(AppSpacing.cardPadding.w),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.card.r),
            border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${pending.vendorName} wants to redeem ₹${pending.amount.toStringAsFixed(2)}',
                style: AppTypography.titleSmall,
              ),
              Gap(4.h),
              Text(
                'Read this code to the store staff to confirm — never share it anywhere else.',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              Gap(AppSpacing.sm.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    pending.otp ?? '······',
                    style: AppTypography.headlineMedium.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 6,
                    ),
                  ),
                  Text(
                    'Expires in ${minutes}m ${seconds.toString().padLeft(2, '0')}s',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
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
      backgroundColor:
          isDark ? AppColors.darkSurfaceContainer : AppColors.surface,
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
                  style: premiumFont(14, weight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Gap(2.h),
                Text(
                  transaction.createdAt.toDayDate,
                  style: premiumFont(11,
                      weight: FontWeight.w400, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            '${isCredit ? '+' : '-'}₹${transaction.amount.toStringAsFixed(2)}',
            style: premiumFont(15, weight: FontWeight.w800, color: amountColor),
          ),
        ],
      ),
    );
  }
}

/// Custom "Add Money" sheet content — matches the reference mock's larger
/// amount field, preset chips, secure/instant/Razorpay info strip and
/// gradient CTA. Kept as its own StatefulWidget (rather than the generic
/// [AppBottomSheet]) since it needs live state for the amount field and
/// chip selection that a plain callback-based sheet body can't hold.
class _AddMoneySheetContent extends StatefulWidget {
  const _AddMoneySheetContent({this.initialAmount});

  final double? initialAmount;

  @override
  State<_AddMoneySheetContent> createState() => _AddMoneySheetContentState();
}

class _AddMoneySheetContentState extends State<_AddMoneySheetContent> {
  static const _presets = <double>[100, 250, 500, 1000];
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialAmount != null
          ? widget.initialAmount!.toStringAsFixed(0)
          : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = double.tryParse(_controller.text.trim());
    if (value == null || value < 10 || value > 10000) {
      AppSnackBar.showError(
          context, 'Enter an amount between ₹10 and ₹10,000.');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.pagePaddingH.w,
          AppSpacing.lg.h,
          AppSpacing.pagePaddingH.w,
          AppSpacing.lg.h,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                          'Add Money to Wallet',
                          style: premiumFont(21, weight: FontWeight.w800),
                        ),
                        Gap(6.h),
                        Text(
                          'Add balance for faster checkout, wallet\npayments and refunds.',
                          style: premiumFont(
                            12.5,
                            weight: FontWeight.w400,
                            color: AppColors.textSecondary,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Gap(8.w),
                  Image.asset(
                    AssetConstants.walletCoinBadge,
                    width: 74.r,
                    height: 74.r,
                  ),
                ],
              ),
              Gap(AppSpacing.lg.h),
              Row(
                children: [
                  Text('Enter amount', style: premiumFont(14, weight: FontWeight.w700)),
                  Gap(8.w),
                  Text(
                    '₹10 – ₹10,000',
                    style: premiumFont(12.5,
                        weight: FontWeight.w500,
                        color: AppColors.textSecondary),
                  ),
                ],
              ),
              Gap(10.h),
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm.w, vertical: 2.h),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurfaceContainer : Colors.white,
                  border: Border.all(color: AppColors.primary, width: 1.6),
                  borderRadius: BorderRadius.circular(AppRadius.md.r),
                ),
                child: Row(
                  children: [
                    Text('₹', style: premiumFont(14, weight: FontWeight.w700)),
                    Gap(4.w),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        autofocus: widget.initialAmount == null,
                        keyboardType: TextInputType.number,
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: const [],
                        style: premiumFont(15, weight: FontWeight.w700),
                        decoration: InputDecoration(
                          isDense: true,
                          isCollapsed: true,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          focusedErrorBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          hintText: 'e.g. 500',
                          hintStyle: premiumFont(15,
                              weight: FontWeight.w700,
                              color: AppColors.textMuted),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Gap(AppSpacing.md.h),
              Row(
                children: [
                  for (var i = 0; i < _presets.length; i++) ...[
                    Expanded(
                      child: _AmountPillChip(
                        label: '₹${_presets[i].toInt()}',
                        onTap: () => setState(
                          () =>
                              _controller.text = _presets[i].toStringAsFixed(0),
                        ),
                      ),
                    ),
                    if (i != _presets.length - 1) Gap(8.w),
                  ],
                ],
              ),
              Gap(AppSpacing.lg.h),
              Container(
                padding: EdgeInsets.symmetric(
                    vertical: AppSpacing.md.h, horizontal: AppSpacing.sm.w),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkSurfaceContainer
                      : AppColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(AppRadius.lg.r),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _SheetInfoBadge(
                        icon: Image.asset(AssetConstants.walletSecureIcon,
                            width: 36.r, height: 36.r),
                        label: 'Secure\ntop-up',
                      ),
                    ),
                    _sheetDivider(isDark),
                    Expanded(
                      child: _SheetInfoBadge(
                        icon: Image.asset(AssetConstants.walletInstantIcon,
                            width: 36.r, height: 36.r),
                        label: 'Instant\nwallet credit',
                      ),
                    ),
                    _sheetDivider(isDark),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Powered by',
                            style: premiumFont(10.5,
                                weight: FontWeight.w500,
                                color: AppColors.textSecondary),
                          ),
                          Gap(5.h),
                          Image.asset(AssetConstants.razorpayLogo,
                              height: 22.h),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Gap(AppSpacing.lg.h),
              SizedBox(
                width: double.infinity,
                height: 54.h,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(AppRadius.button.r),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.button.r),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.button.r),
                      onTap: _submit,
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Proceed to Pay',
                              style: premiumFont(16,
                                  weight: FontWeight.w700, color: Colors.white),
                            ),
                            Gap(8.w),
                            Icon(Icons.arrow_forward_rounded,
                                color: Colors.white, size: 18.r),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetDivider(bool isDark) => Container(
        width: 1,
        height: 40.h,
        color: isDark ? AppColors.darkOutlineVariant : AppColors.outlineVariant,
      );
}

class _SheetInfoBadge extends StatelessWidget {
  const _SheetInfoBadge({required this.icon, required this.label});

  final Widget icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        Gap(4.h),
        Text(
          label,
          textAlign: TextAlign.center,
          style: premiumFont(10, weight: FontWeight.w600, height: 1.2),
        ),
      ],
    );
  }
}
