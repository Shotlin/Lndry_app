import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../../../config/env.dart';
import '../../../../core/constants/asset_constants.dart';
import '../../../../core/design/design_system.dart';
import '../../../../core/extensions/extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../models/models.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../repositories/repositories.dart';
import '../../../cart/presentation/providers/cart_providers.dart';
import '../../../checkout/presentation/pages/checkout_page.dart';
import '../../../checkout/presentation/widgets/checkout_brand_header.dart';
import '../../../home/presentation/providers/home_providers.dart';
import '../../../wallet/presentation/providers/wallet_providers.dart';
import '../controllers/razorpay_payment_controller.dart';
import '../providers/assisted_booking_provider.dart';
import '../providers/checkout_content_provider.dart';
import '../../../../core/network/friendly_error.dart';

/// Display-only fallback for the "Pay Now (Advance)" figure while the real
/// payment order is still loading from the server — the actual Razorpay
/// charge always comes from `createPaymentOrder`'s response, never this
/// constant. Matches the `order_advance_amount_paise` default (5000 paise).
const double _fallbackAdvanceDisplay = 50.0;

class PaymentPage extends ConsumerStatefulWidget {
  const PaymentPage({super.key});

  @override
  ConsumerState<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends ConsumerState<PaymentPage> {
  late final RazorpayPaymentController _paymentController;
  bool _isProcessing = false;
  bool _isVerifyingPayment = false;
  bool _paymentFinalized = false;
  bool _verificationRetryPending = false;
  bool _isLoadingPaymentOrder = true;
  // Governs only how the BALANCE is settled at delivery — every order pays
  // the same fixed advance online here first, since there's no one present
  // to hand cash to at checkout time. Cash on Delivery was removed as an
  // option (business decision) — the balance is now always settled online
  // too, so this only tracks which online method the customer prefers.
  String _selectedMethod = 'upi';
  PaymentOrderResult? _pendingPaymentOrder;
  CheckoutSession? _pendingSession;
  PaymentSuccessResponse? _pendingSuccessResponse;

  @override
  void initState() {
    super.initState();
    _paymentController = RazorpayPaymentController(
      onSuccess: _handlePaymentSuccess,
      onFailure: _handlePaymentFailure,
      onExternalWallet: _handleExternalWallet,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPaymentOrder());
  }

  @override
  void dispose() {
    _paymentController.dispose();
    super.dispose();
  }

  /// Creates the (advance) payment order once, up front, so the summary
  /// card can show the real server-computed advance/balance split before
  /// the customer even taps Pay — the same order is then reused when they
  /// do, rather than creating a second one.
  Future<void> _loadPaymentOrder() async {
    final session = GoRouterState.of(context).extra as CheckoutSession?;
    _pendingSession = session;

    final isMockMode = Env.useMocksForVisualTestsOnly || ref.read(useMocksProvider);
    if (!isMockMode && (session?.orderDraftId == null || session!.orderDraftId!.isEmpty)) {
      if (mounted) setState(() => _isLoadingPaymentOrder = false);
      return;
    }

    try {
      final repo = ref.read(customerRepositoryProvider);
      final paymentResult = await repo.createPaymentOrder(orderDraftId: session?.orderDraftId);
      if (mounted) {
        setState(() {
          _pendingPaymentOrder = paymentResult;
          _isLoadingPaymentOrder = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingPaymentOrder = false);
        AppSnackBar.showError(context, 'Could not prepare payment: ${friendlyError(e)}');
      }
    }
  }

  Future<void> _processPayment(CartState cart) async {
    if (_isProcessing || _isVerifyingPayment || _paymentFinalized || _isLoadingPaymentOrder) return;

    if (_verificationRetryPending && _pendingSuccessResponse != null) {
      await _verifyAndPlaceOrder(_pendingSuccessResponse!);
      return;
    }

    final session = _pendingSession;

    // A "Book With Expert Check" booking has no cart by design.
    if (!(session?.isAssisted ?? false) && cart.cart.isEmpty) {
      if (mounted) {
        AppSnackBar.showError(context, 'Your cart is empty.');
        context.go(AppRoutes.vendorListing);
      }
      return;
    }

    final repo = ref.read(customerRepositoryProvider);

    try {
      final isMockMode = Env.useMocksForVisualTestsOnly || ref.read(useMocksProvider);

      setState(() => _isProcessing = true);

      if (!isMockMode) {
        final paymentResult = _pendingPaymentOrder;
        if (session?.orderDraftId == null || session!.orderDraftId!.isEmpty || paymentResult == null) {
          if (mounted) {
            setState(() => _isProcessing = false);
            AppSnackBar.showError(
              context,
              'Checkout quote is unavailable. Please retry checkout.',
            );
          }
          return;
        }

        final gatewayKey = _gatewayKey(paymentResult);

        if (gatewayKey.isEmpty) {
          if (mounted) {
            setState(() => _isProcessing = false);
            AppSnackBar.showError(
              context,
              'Payment gateway is not configured for this build.',
            );
          }
          return;
        }

        if (paymentResult.razorpayOrderId.isEmpty) {
          if (mounted) {
            setState(() => _isProcessing = false);
            AppSnackBar.showError(
              context,
              'Payment order is unavailable. Please retry checkout.',
            );
          }
          return;
        }

        _pendingSuccessResponse = null;
        _verificationRetryPending = false;

        _paymentController.open(_buildCheckoutOptions(
          paymentResult: paymentResult,
          gatewayKey: gatewayKey,
          amountDue: paymentResult.amount,
        ));
        return;
      }

      // Development mock mode only: simulate a Razorpay transaction.
      final paymentResult = _pendingPaymentOrder ??
          await repo.createPaymentOrder(orderDraftId: session?.orderDraftId);
      await Future<void>.delayed(const Duration(milliseconds: 1800));

      // Development mock mode only: verify using mock repository semantics.
      final verifyResult = await repo.verifyPayment(
        razorpayOrderId: paymentResult.razorpayOrderId,
        razorpayPaymentId: 'rzp_pay_${DateTime.now().millisecondsSinceEpoch}',
        razorpaySignature: 'mock_signature',
        orderDraftId: session?.orderDraftId,
      );

      if (!verifyResult.success) {
        if (mounted) {
          setState(() => _isProcessing = false);
          AppSnackBar.showError(context, 'Payment verification failed.');
        }
        return;
      }

      await _placeOrderAfterVerifiedPayment(session: session, cart: cart);
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        AppSnackBar.showError(context, 'Transaction failed: ${friendlyError(e)}');
      }
    }
  }

  /// Pays the advance directly from LNDRY wallet balance — skips Razorpay
  /// entirely. The backend marks the payments row PAID in the same step
  /// (no separate verify call needed), so this goes straight to placing
  /// the order, mirroring what `_verifyAndPlaceOrder` does after a Razorpay
  /// verification succeeds.
  Future<void> _payWithWallet() async {
    if (_isProcessing || _isVerifyingPayment || _paymentFinalized) return;

    final session = _pendingSession;
    if (session?.orderDraftId == null || session!.orderDraftId!.isEmpty) {
      AppSnackBar.showError(
        context,
        'Checkout quote is unavailable. Please retry checkout.',
      );
      return;
    }

    setState(() {
      _isProcessing = true;
      _isVerifyingPayment = true;
    });

    try {
      final result = await ref.read(customerRepositoryProvider).payWithWallet(
            orderDraftId: session.orderDraftId,
          );

      if (!result.success) {
        if (!mounted) return;
        setState(() {
          _isProcessing = false;
          _isVerifyingPayment = false;
        });
        AppSnackBar.showError(
          context,
          result.message ?? 'Wallet payment failed.',
        );
        return;
      }

      _paymentFinalized = true;
      ref.invalidate(walletProvider);
      ref.invalidate(walletTransactionsProvider);
      await _placeOrderAfterVerifiedPayment(session: session, cart: null);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _isVerifyingPayment = false;
      });
      AppSnackBar.showError(context, 'Wallet payment failed: ${friendlyError(e)}');
    }
  }

  Map<String, dynamic> _buildCheckoutOptions({
    required PaymentOrderResult paymentResult,
    required String gatewayKey,
    required double amountDue,
  }) {
    final user = ref.read(currentUserProvider);
    final amountPaise =
        paymentResult.amount > 0 ? (paymentResult.amount * 100).round() : 0;

    return <String, dynamic>{
      'key': gatewayKey,
      'order_id': paymentResult.razorpayOrderId,
      if (amountPaise > 0) 'amount': amountPaise,
      'currency': paymentResult.currency,
      'name': 'LNDRY',
      'description': 'Laundry order payment',
      'timeout': 300,
      'prefill': <String, dynamic>{
        if (user?.name.isNotEmpty == true) 'name': user!.name,
        if (user?.phone.isNotEmpty == true) 'contact': user!.phone,
        if (user?.email?.isNotEmpty == true) 'email': user!.email,
      },
      'notes': <String, dynamic>{
        if (_pendingSession?.orderDraftId?.isNotEmpty == true)
          'orderDraftId': _pendingSession!.orderDraftId,
        'paymentId': paymentResult.paymentId,
        'amountDue': amountDue.toStringAsFixed(2),
      },
    };
  }

  String _gatewayKey(PaymentOrderResult result) {
    final backendKey = result.keyId;
    if (backendKey != null && backendKey.isNotEmpty) return backendKey;
    return Env.razorpayKey;
  }

  Future<void> _handlePaymentSuccess(PaymentSuccessResponse response) async {
    // Dedup of redelivered gateway events is handled by RazorpayPaymentController.
    _pendingSuccessResponse = response;
    await _verifyAndPlaceOrder(response);
  }

  Future<void> _verifyAndPlaceOrder(PaymentSuccessResponse response) async {
    if (_isVerifyingPayment || _paymentFinalized) return;

    final pendingOrder = _pendingPaymentOrder;
    final session = _pendingSession;
    final razorpayOrderId = response.orderId?.isNotEmpty == true
        ? response.orderId!
        : pendingOrder?.razorpayOrderId;
    final razorpayPaymentId = response.paymentId;
    final razorpaySignature = response.signature;

    if (pendingOrder == null ||
        session?.orderDraftId == null ||
        razorpayOrderId == null ||
        razorpayOrderId.isEmpty ||
        razorpayPaymentId == null ||
        razorpayPaymentId.isEmpty ||
        razorpaySignature == null ||
        razorpaySignature.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _isVerifyingPayment = false;
      });
      AppSnackBar.showError(
        context,
        'Payment response was incomplete. Please contact support.',
      );
      return;
    }

    setState(() {
      _isProcessing = true;
      _isVerifyingPayment = true;
      _verificationRetryPending = false;
    });

    try {
      final verifyResult =
          await ref.read(customerRepositoryProvider).verifyPayment(
                razorpayOrderId: razorpayOrderId,
                razorpayPaymentId: razorpayPaymentId,
                razorpaySignature: razorpaySignature,
                orderDraftId: session!.orderDraftId,
              );

      if (!verifyResult.success) {
        if (!mounted) return;
        setState(() {
          _isProcessing = false;
          _isVerifyingPayment = false;
        });
        AppSnackBar.showError(context, 'Payment verification failed.');
        return;
      }

      _paymentFinalized = true;
      await _placeOrderAfterVerifiedPayment(session: session, cart: null);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _isVerifyingPayment = false;
        _verificationRetryPending = true;
      });
      AppSnackBar.showError(
        context,
        'Payment captured, but verification could not be completed. Tap Verify Payment to retry.',
      );
    }
  }

  void _handlePaymentFailure(PaymentFailureResponse response) {
    if (_paymentFinalized) return;

    final isCancel = response.code == 2 ||
        (response.message ?? '').toLowerCase().contains('cancel');

    // Deliberately keep _pendingPaymentOrder/_pendingSession — they're the
    // one payment order fetched up front in _loadPaymentOrder and reused
    // across retries, unlike before when a fresh one was created per attempt.
    _pendingSuccessResponse = null;

    if (!mounted) return;
    setState(() {
      _isProcessing = false;
      _isVerifyingPayment = false;
      _verificationRetryPending = false;
    });

    AppSnackBar.showError(
      context,
      isCancel
          ? 'Payment cancelled. You can retry safely.'
          : 'Payment failed. Please try another payment method.',
    );
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    if (!mounted || _paymentFinalized) return;
    AppSnackBar.showSuccess(
        context, 'Wallet selected. Complete payment to continue.');
  }

  Future<void> _placeOrderAfterVerifiedPayment({
    required CheckoutSession? session,
    required CartState? cart,
  }) async {
    final repo = ref.read(customerRepositoryProvider);

    final PlaceOrderRequest placeRequest;
    if (session?.orderDraftId != null) {
      placeRequest = PlaceOrderRequest(
        orderDraftId: session!.orderDraftId,
      );
    } else {
      final addressId = session?.deliveryAddressId;
      final currentCart = cart;
      final selectedSlot = session?.selectedSlot;
      final isMockMode = Env.useMocksForVisualTestsOnly || ref.read(useMocksProvider);
      if (!isMockMode ||
          addressId == null ||
          addressId.isEmpty ||
          selectedSlot == null ||
          selectedSlot.isEmpty ||
          currentCart == null ||
          currentCart.services.isEmpty) {
        if (mounted) {
          setState(() => _isProcessing = false);
          AppSnackBar.showError(
            context,
            'Checkout session is unavailable. Please retry checkout.',
          );
        }
        return;
      }
      placeRequest = PlaceOrderRequest(
        vendorId: currentCart.services.first.vendorId,
        vendorSlotId: selectedSlot,
        items: currentCart.cart.items
            .map((i) => OrderItemRequest(
                  serviceId: i.serviceId,
                  quantity: i.quantity,
                ))
            .toList(),
        deliveryAddressId: addressId,
        pickupAddressId: session?.pickupAddressId ?? addressId,
        paymentMethod: _resolvePaymentMethod(_selectedMethod),
      );
    }

    final placedOrder = await repo.placeOrder(placeRequest);
    // An assisted booking never used the cart, so leave whatever the customer
    // has in it alone.
    if (!(session?.isAssisted ?? false)) {
      ref.read(cartStateProvider.notifier).clear();
    }
    // The Orders list/Home screen otherwise wouldn't know this order
    // exists until their next pull-to-refresh — invalidate right away so
    // it's there the moment the customer navigates back to either screen.
    ref.invalidate(activeOrdersProvider);
    ref.invalidate(pastOrdersProvider);

    if (mounted) {
      setState(() {
        _isProcessing = false;
        _isVerifyingPayment = false;
        _verificationRetryPending = false;
      });
      final isMock = Env.useMocksForVisualTestsOnly || ref.read(useMocksProvider);
      AppSnackBar.showSuccess(
        context,
        isMock ? 'Demo Mode: Payment Successful!' : 'Payment Successful!',
      );
      context.go(
        Uri(
          path: '/orders/${placedOrder.id}/submitted',
          queryParameters: placedOrder.orderNumber.isNotEmpty
              ? {'orderNumber': placedOrder.orderNumber}
              : null,
        ).toString(),
      );
    }
  }

  PaymentMethod _resolvePaymentMethod(String method) => switch (method) {
        'upi' => PaymentMethod.upi,
        'card' => PaymentMethod.card,
        'wallet' => PaymentMethod.wallet,
        'lndry_wallet' => PaymentMethod.lndryWallet,
        _ => PaymentMethod.online,
      };

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final isDark = theme.brightness == Brightness.dark;
    final cartState = ref.watch(cartStateProvider);
    final session = GoRouterState.of(context).extra as CheckoutSession?;
    final isAssisted = session?.isAssisted ?? false;
    final assistedConfig = isAssisted
        ? (ref
                .watch(assistedBookingConfigProvider(
                    session?.assistedVendorId ?? ''))
                .value ??
            AssistedBookingConfig.fallback)
        : AssistedBookingConfig.fallback;
    final estimatedTotal = session?.finalPrice ?? cartState.total;
    final advanceDue = _pendingPaymentOrder?.amount ??
        (session?.advanceAmountPaise != null
            ? session!.advanceAmountPaise! / 100.0
            : _fallbackAdvanceDisplay);
    // Admin-editable copy; `.value` is null only while the first fetch is in
    // flight, so the built-in text shows instead of a blank banner.
    final checkoutContent =
        ref.watch(checkoutContentProvider).value ?? CheckoutContent.fallback;
    final balanceDue = (estimatedTotal - advanceDue).clamp(0, double.infinity);
    final walletAsync = ref.watch(walletProvider);
    final walletBalance = walletAsync.value?.balance;
    final isWalletSelected = _selectedMethod == 'lndry_wallet';
    final walletInsufficient =
        isWalletSelected && walletBalance != null && walletBalance < advanceDue;

    final paymentCtaLabel = _verificationRetryPending
        ? 'Verify Payment'
        : _isLoadingPaymentOrder
            ? 'Preparing...'
            : isWalletSelected
                ? (walletInsufficient
                    ? 'Insufficient Wallet Balance'
                    : 'Pay ${advanceDue.toCurrencyDecimal} with Wallet')
                : 'Pay ${advanceDue.toCurrencyDecimal} Now';
    final isCtaBusy = _isLoadingPaymentOrder && !_verificationRetryPending;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : Colors.white,
      appBar: CheckoutBrandHeader(
        isDark: isDark,
        onBack: () => context.pop(),
        subtitle: 'Secure payment powered by Razorpay',
      ),
      body: SafeArea(
        top: false,
        child: _isProcessing
            ? const AppLoadingPage(
                message: 'Securing transaction with Razorpay...')
            : (!isAssisted && cartState.cart.isEmpty)
                ? AppEmptyState(
                    icon: AppIcons.cartOutlined,
                    title: 'Nothing to pay for',
                    subtitle:
                        'Your cart is empty. Add services before completing payment.',
                    actionLabel: 'Browse vendors',
                    onAction: () => context.go(AppRoutes.vendorListing),
                  )
                : Column(
                    children: [
                      _CheckoutStepper(isDark: isDark),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                            AppSpacing.pagePaddingH.w,
                            AppSpacing.md.h,
                            AppSpacing.pagePaddingH.w,
                            AppSpacing.md.h,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Payment Summary card — the towel/"Fresh Looks
                              // Better" art anchors the header the way the
                              // approved reference design does.
                              _PaymentSummaryCard(
                                isDark: isDark,
                                estimatedTotal: estimatedTotal,
                                advanceDue: advanceDue,
                                balanceDue: balanceDue.toDouble(),
                                assistedConfig: isAssisted ? assistedConfig : null,
                              ),
                              const Gap(14),

                              // Shirt + checkmark art pairs with the plain-
                              // English explanation of what the advance buys.
                              _ConfirmPickupBanner(
                                isDark: isDark,
                                advanceDue: advanceDue,
                                content: checkoutContent,
                              ),
                              const Gap(12),

                              // Refund guarantee — the advance is charged
                              // before the slot is actually confirmed, so
                              // this explicitly promises a refund if that
                              // confirmation never comes.
                              _RefundGuaranteeBanner(
                                isDark: isDark,
                                advanceDue: advanceDue,
                                content: checkoutContent,
                              ),
                              const Gap(28),

                              Row(
                                children: [
                                  Text(
                                    'Select Payment Method',
                                    style: AppTypography.titleMedium.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: isDark
                                          ? AppColors.darkTextPrimary
                                          : AppColors.lightTextPrimary,
                                    ),
                                  ),
                                  const Gap(8),
                                  const _RecommendedPill(),
                                ],
                              ),
                              const Gap(4),
                              Text(
                                'How you\'d like to pay — both the advance now and the balance at delivery.',
                                style: AppTypography.caption
                                    .copyWith(color: AppColors.onSurfaceVariant),
                              ),
                              const Gap(16),

                              // Payment options list
                              _PaymentMethodTile(
                                label: 'UPI (GPay / PhonePe / Paytm)',
                                subtitle: 'Fast, secure and easy',
                                icon: Icons.qr_code_rounded,
                                iconBackground: AppColors.secondaryLight,
                                iconColor: AppColors.secondaryDark,
                                isSelected: _selectedMethod == 'upi',
                                onTap: () =>
                                    setState(() => _selectedMethod = 'upi'),
                              ),
                              const Gap(12),
                              _PaymentMethodTile(
                                label: 'Credit / Debit Card',
                                subtitle: 'Visa, Mastercard, Rupay & more',
                                icon: AppIcons.creditCard,
                                iconBackground: AppColors.primaryContainer,
                                iconColor: AppColors.primary,
                                isSelected: _selectedMethod == 'card',
                                onTap: () =>
                                    setState(() => _selectedMethod = 'card'),
                              ),
                              const Gap(12),
                              _PaymentMethodTile(
                                label: 'Wallets',
                                subtitle: 'Amazon Pay, PhonePe, Paytm & more',
                                icon: AppIcons.walletOutlined,
                                iconBackground: AppColors.aquaTint,
                                iconColor: AppColors.aquaDeep,
                                isSelected: _selectedMethod == 'wallet',
                                onTap: () =>
                                    setState(() => _selectedMethod = 'wallet'),
                              ),
                              const Gap(12),
                              _PaymentMethodTile(
                                label: 'LNDRY Wallet',
                                subtitle: walletAsync.when(
                                  data: (w) =>
                                      'Balance: ${w.balance.toCurrencyDecimal}',
                                  loading: () => 'Loading balance...',
                                  error: (_, __) => 'Balance unavailable',
                                ),
                                icon: AppIcons.wallet,
                                iconBackground: AppColors.tertiaryContainer,
                                iconColor: AppColors.tertiary,
                                isSelected: isWalletSelected,
                                onTap: () => setState(
                                    () => _selectedMethod = 'lndry_wallet'),
                              ),
                              const Gap(28),

                              const _TrustBadgeRow(),
                            ],
                          ),
                        ),
                      ),
                      _PaymentBottomBar(
                        isDark: isDark,
                        advanceDue: advanceDue,
                        ctaLabel: paymentCtaLabel,
                        isBusy: isCtaBusy,
                        isDisabled: (_isLoadingPaymentOrder && !_verificationRetryPending) ||
                            walletInsufficient,
                        onPressed: isWalletSelected
                            ? _payWithWallet
                            : () => _processPayment(cartState),
                      ),
                    ],
                  ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STEPPER — Address (done) → Payment (active) → Confirm (upcoming)
// ═══════════════════════════════════════════════════════════════════════════

enum _StepState { done, active, upcoming }

class _CheckoutStepper extends StatelessWidget {
  const _CheckoutStepper({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: isDark ? AppColors.darkBackground : Colors.white,
      padding: EdgeInsets.fromLTRB(28.w, 2.h, 28.w, 18.h),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StepNode(label: 'Address', state: _StepState.done),
          Expanded(child: _StepConnector(active: true)),
          _StepNode(label: 'Payment', state: _StepState.active, number: 2),
          Expanded(child: _StepConnector(active: false)),
          _StepNode(label: 'Confirm', state: _StepState.upcoming, number: 3),
        ],
      ),
    );
  }
}

class _StepNode extends StatelessWidget {
  const _StepNode({required this.label, required this.state, this.number});

  final String label;
  final _StepState state;
  final int? number;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final isActive = state == _StepState.active;
    final isDone = state == _StepState.done;
    final isFilled = isActive || isDone;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32.r,
          height: 32.r,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isFilled
                ? AppColors.primary
                : (isDark ? AppColors.darkSurfaceContainer : Colors.white),
            border: Border.all(
              color: isFilled ? AppColors.primary : AppColors.outlineVariant,
              width: 1.5,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: isDone
                ? Icon(Icons.check_rounded, size: 16.r, color: Colors.white)
                : Text(
                    '$number',
                    style: AppTypography.labelMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isActive ? Colors.white : AppColors.onSurfaceVariant,
                    ),
                  ),
          ),
        ),
        const Gap(6),
        Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: isActive
                ? AppColors.primary
                : isDone
                    ? (isDark ? AppColors.darkTextBody : AppColors.lightTextBody)
                    : AppColors.onSurfaceVariant,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _StepConnector extends StatelessWidget {
  const _StepConnector({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32.r,
      child: Center(
        child: Container(
          height: 2,
          margin: EdgeInsets.symmetric(horizontal: 6.w),
          color: active ? AppColors.primary : AppColors.outlineVariant,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PAYMENT SUMMARY CARD
// ═══════════════════════════════════════════════════════════════════════════

class _PaymentSummaryCard extends StatelessWidget {
  const _PaymentSummaryCard({
    required this.isDark,
    required this.estimatedTotal,
    required this.advanceDue,
    required this.balanceDue,
    this.assistedConfig,
  });

  final bool isDark;
  final double estimatedTotal;
  final double advanceDue;
  final double balanceDue;

  /// Set for "Book With Expert Check": there is no service price yet, so the
  /// summary shows the admin-editable "price after inspection" wording instead
  /// of an estimate and a balance.
  final AssistedBookingConfig? assistedConfig;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(18.r),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceContainer : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.xxl.r),
        boxShadow: isDark ? null : AppElevation.medium,
        border: isDark
            ? Border.all(color: AppColors.darkOutlineVariant)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Payment Summary',
                      style: AppTypography.titleLarge.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary,
                      ),
                    ),
                    const Gap(4),
                    Text(
                      assistedConfig != null
                          ? assistedConfig!.checkoutNote
                          : 'Final amount may vary after vendor weighs your items.',
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const Gap(6),
              Image.asset(
                AssetConstants.paymentFreshTowelsBanner,
                height: 84.h,
                fit: BoxFit.contain,
              ),
            ],
          ),
          const Gap(18),
          if (assistedConfig != null)
            _SummaryLineItem(
              icon: AppIcons.document,
              label: 'Service price',
              valueText: assistedConfig!.priceLabel,
              amount: 0,
            )
          else
            _SummaryLineItem(
              icon: AppIcons.document,
              label: 'Total order estimate',
              amount: estimatedTotal,
            ),
          const Gap(10),
          _SummaryHighlightItem(
            icon: AppIcons.creditCard,
            title: 'Pay now to book slot',
            subtitle: 'This confirms your pickup',
            amount: advanceDue,
          ),
          const Gap(10),
          if (assistedConfig != null)
            _SummaryLineItem(
              icon: AppIcons.clock,
              label: 'Pay later after final check',
              subtitle:
                  'After you approve the services and price the laundry confirms. This advance is adjusted against it.',
              valueText: 'After inspection',
              amount: 0,
              muted: true,
            )
          else
            _SummaryLineItem(
              icon: AppIcons.clock,
              label: 'Pay later after final check',
              subtitle: 'After the vendor weighs your clothes',
              amount: balanceDue,
              muted: true,
            ),
        ],
      ),
    );
  }
}

class _SummaryLineItem extends StatelessWidget {
  const _SummaryLineItem({
    required this.icon,
    required this.label,
    required this.amount,
    this.valueText,
    this.subtitle,
    this.muted = false,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final double amount;

  /// Shown instead of [amount] when set (e.g. "Price after inspection").
  final String? valueText;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final primaryTextColor =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 18.r, color: AppColors.onSurfaceVariant),
        const Gap(10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTypography.bodyMedium.copyWith(
                  color: muted ? AppColors.onSurfaceVariant : primaryTextColor,
                ),
              ),
              if (subtitle != null) ...[
                const Gap(2),
                Text(
                  subtitle!,
                  style: AppTypography.caption
                      .copyWith(color: AppColors.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
        const Gap(8),
        Text(
          valueText ?? amount.toCurrencyDecimal,
          style: AppTypography.titleSmall.copyWith(
            fontWeight: FontWeight.w700,
            color: muted ? AppColors.onSurfaceVariant : primaryTextColor,
          ),
        ),
      ],
    );
  }
}

class _SummaryHighlightItem extends StatelessWidget {
  const _SummaryHighlightItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.amount,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final double amount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.md.r),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 34.r,
            height: 34.r,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(AppRadius.sm.r),
            ),
            child: Icon(icon, size: 17.r, color: Colors.white),
          ),
          const Gap(10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark,
                  ),
                ),
                const Gap(2),
                Text(
                  subtitle,
                  style: AppTypography.caption
                      .copyWith(color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const Gap(8),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(AppRadius.full.r),
            ),
            child: Text(
              amount.toCurrencyDecimal,
              style: AppTypography.titleSmall
                  .copyWith(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CONFIRM-PICKUP BANNER (shirt + checkmark art)
// ═══════════════════════════════════════════════════════════════════════════

class _ConfirmPickupBanner extends StatelessWidget {
  const _ConfirmPickupBanner({
    required this.isDark,
    required this.advanceDue,
    required this.content,
  });

  final bool isDark;
  final double advanceDue;
  final CheckoutContent content;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(14.r),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceContainer : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg.r),
        border: Border.all(
          color: isDark
              ? AppColors.darkOutlineVariant
              : AppColors.primary.withValues(alpha: 0.10),
        ),
        boxShadow: isDark ? null : AppElevation.low,
      ),
      child: Row(
        children: [
          Image.asset(
            AssetConstants.paymentShirtConfirmBadge,
            height: 76.h,
            fit: BoxFit.contain,
          ),
          const Gap(14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  CheckoutContent.withAmount(
                      content.advanceTitle, advanceDue.toCurrencyDecimal),
                  style: AppTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppColors.darkTextPrimary
                        : AppColors.lightTextPrimary,
                  ),
                ),
                const Gap(4),
                Text(
                  CheckoutContent.withAmount(
                      content.advanceSubtitle, advanceDue.toCurrencyDecimal),
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// REFUND GUARANTEE BANNER
// ═══════════════════════════════════════════════════════════════════════════

class _RefundGuaranteeBanner extends StatelessWidget {
  const _RefundGuaranteeBanner({
    required this.isDark,
    required this.advanceDue,
    required this.content,
  });

  final bool isDark;
  final double advanceDue;
  final CheckoutContent content;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 20.h),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceContainer : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg.r),
        border: Border.all(
          color: isDark
              ? AppColors.darkOutlineVariant
              : AppColors.primary.withValues(alpha: 0.10),
        ),
        boxShadow: isDark ? null : AppElevation.low,
      ),
      child: Column(
        children: [
          Container(
            width: 46.r,
            height: 46.r,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.verified_rounded, color: Colors.white, size: 26.r),
          ),
          const Gap(12),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text:
                      '${CheckoutContent.withAmount(content.refundTitle, advanceDue.toCurrencyDecimal)} ',
                  style: AppTypography.bodySmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textBlack,
                  ),
                ),
                TextSpan(
                  text: CheckoutContent.withAmount(
                      content.refundBody, advanceDue.toCurrencyDecimal),
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textBlack),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// "RECOMMENDED" PILL
// ═══════════════════════════════════════════════════════════════════════════

class _RecommendedPill extends StatelessWidget {
  const _RecommendedPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: AppColors.secondaryLight,
        borderRadius: BorderRadius.circular(AppRadius.full.r),
      ),
      child: Text(
        'Recommended',
        style: AppTypography.labelSmall.copyWith(
          color: AppColors.secondaryDark,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PAYMENT METHOD TILE
// ═══════════════════════════════════════════════════════════════════════════

class _PaymentMethodTile extends StatelessWidget {
  const _PaymentMethodTile({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.iconBackground,
    required this.iconColor,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final Color iconBackground;
  final Color iconColor;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final primaryTextColor =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.lg.r),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg.r),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.all(14.r),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primaryContainer.withValues(alpha: isDark ? 0.18 : 0.6)
                : (isDark ? AppColors.darkSurfaceContainer : Colors.white),
            borderRadius: BorderRadius.circular(AppRadius.lg.r),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.outlineVariant,
              width: isSelected ? 1.6 : 1,
            ),
            boxShadow: isSelected && !isDark ? AppElevation.low : null,
          ),
          child: Row(
            children: [
              Container(
                width: 44.r,
                height: 44.r,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(AppRadius.md.r),
                ),
                child: Icon(icon, color: iconColor, size: 22.r),
              ),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppTypography.titleSmall.copyWith(
                        fontWeight: FontWeight.w700,
                        color: primaryTextColor,
                      ),
                    ),
                    const Gap(2),
                    Text(
                      subtitle,
                      style: AppTypography.caption
                          .copyWith(color: AppColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const Gap(8),
              _RadioDot(isSelected: isSelected),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.isSelected});

  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22.r,
      height: 22.r,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? AppColors.primary : AppColors.outline,
          width: 2,
        ),
      ),
      child: isSelected
          ? Center(
              child: Container(
                width: 11.r,
                height: 11.r,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
            )
          : null,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TRUST BADGE ROW
// ═══════════════════════════════════════════════════════════════════════════

class _TrustBadgeRow extends StatelessWidget {
  const _TrustBadgeRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(
          child: _TrustBadge(
            icon: Icons.lock_rounded,
            label: '100% secure\ntransactions',
          ),
        ),
        Expanded(
          child: _TrustBadge(
            icon: Icons.verified_user_rounded,
            label: 'PCI-DSS\ncompliant',
          ),
        ),
        Expanded(
          child: _TrustBadge(
            icon: Icons.shield_rounded,
            label: 'Safe payments\nwith Razorpay',
          ),
        ),
      ],
    );
  }
}

class _TrustBadge extends StatelessWidget {
  const _TrustBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 18.r, color: AppColors.primary),
        const Gap(6),
        Text(
          label,
          textAlign: TextAlign.center,
          style: AppTypography.caption
              .copyWith(color: AppColors.onSurfaceVariant, height: 1.35),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STICKY BOTTOM CTA BAR
// ═══════════════════════════════════════════════════════════════════════════

class _PaymentBottomBar extends StatelessWidget {
  const _PaymentBottomBar({
    required this.isDark,
    required this.advanceDue,
    required this.ctaLabel,
    required this.isBusy,
    required this.isDisabled,
    required this.onPressed,
  });

  final bool isDark;
  final double advanceDue;
  final String ctaLabel;
  final bool isBusy;
  final bool isDisabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20.w,
        14.h,
        20.w,
        MediaQuery.paddingOf(context).bottom + 14.h,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.dialog.r)),
        boxShadow: AppElevation.high,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pay now',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.onSurfaceVariant),
                ),
                const Gap(2),
                Text(
                  advanceDue.toCurrencyDecimal,
                  style: AppTypography.headlineSmall.copyWith(
                    fontWeight: FontWeight.w800,
                    color: isDark
                        ? AppColors.darkTextPrimary
                        : AppColors.lightTextPrimary,
                  ),
                ),
                const Gap(2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_rounded,
                        size: 11.r, color: AppColors.onSurfaceVariant),
                    const Gap(4),
                    Text(
                      'Secure & encrypted',
                      style: AppTypography.caption
                          .copyWith(color: AppColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Gap(14),
          _GradientCtaButton(
            label: ctaLabel,
            isBusy: isBusy,
            isDisabled: isDisabled,
            onPressed: onPressed,
          ),
        ],
      ),
    );
  }
}

class _GradientCtaButton extends StatelessWidget {
  const _GradientCtaButton({
    required this.label,
    required this.isBusy,
    required this.isDisabled,
    required this.onPressed,
  });

  final String label;
  final bool isBusy;
  final bool isDisabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: isDisabled ? 0.55 : 1,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.full.r),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.full.r),
          onTap: isDisabled ? null : onPressed,
          child: Container(
            height: 52.h,
            constraints: BoxConstraints(minWidth: 150.w),
            padding: EdgeInsets.symmetric(horizontal: 22.w),
            decoration: BoxDecoration(
              gradient: AppColors.signInCtaGradient,
              borderRadius: BorderRadius.circular(AppRadius.full.r),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: AppTypography.buttonText.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Gap(8),
                if (isBusy)
                  SizedBox(
                    width: 16.r,
                    height: 16.r,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                else
                  Icon(Icons.arrow_forward_rounded,
                      color: Colors.white, size: 18.r),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
