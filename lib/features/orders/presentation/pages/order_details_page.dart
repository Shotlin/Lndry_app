import 'dart:async';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/design/design_system.dart';
import '../../../../core/extensions/extensions.dart';
import '../../../../core/network/network.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../models/models.dart';
import '../../../../providers/order_sync_provider.dart';
import '../../../../repositories/repositories.dart';
import '../../../../shared/widgets/shared_widgets.dart';
import '../widgets/balance_payment_card.dart';
import '../widgets/order_revision_sheet.dart';
import '../widgets/payment_status_card.dart';

/// A continuous-unit item's (kg/sq ft) real decimal quantity can't live in
/// the INTEGER order_lines.quantity column once a rider/vendor correction
/// is applied (it becomes a sentinel `1`) — derive it from
/// totalPrice/unitPrice instead, which always carries the real money.
String _itemQuantityLabel(OrderItem item) {
  final u = item.unit.toLowerCase();
  if ((u == 'kg' || u == 'sqft') && item.unitPrice > 0) {
    final derived = item.totalPrice / item.unitPrice;
    var s = derived.toStringAsFixed(2);
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return '$s ${u == 'sqft' ? 'sq ft' : 'kg'}';
  }
  return '${item.quantity}';
}

/// Display suffix for a reconciliation line-change's unit, e.g. " kg" / " sq ft".
String _unitSuffix(String? unit) {
  final u = unit?.toLowerCase();
  if (u == 'kg') return ' kg';
  if (u == 'sqft') return ' sq ft';
  return '';
}

/// Whether pickup has actually happened yet — an explicit allowlist rather
/// than an enum-index comparison, since terminal/rejected statuses sort
/// after pickedUp in the enum despite never having reached it.
bool _isPickupDone(OrderStatus status) => const {
      OrderStatus.pickedUp,
      OrderStatus.receivedAtVendor,
      OrderStatus.reconciliationPending,
      OrderStatus.reconciliationDisputed,
      OrderStatus.processing,
      OrderStatus.packed,
      OrderStatus.deliveryAssigned,
      OrderStatus.outForDelivery,
      OrderStatus.deliveryOtpVerified,
      OrderStatus.delivered,
    }.contains(status);

class OrderDetailsPage extends ConsumerStatefulWidget {
  const OrderDetailsPage({required this.orderId, super.key});
  final String orderId;

  @override
  ConsumerState<OrderDetailsPage> createState() => _OrderDetailsPageState();
}

class _OrderDetailsPageState extends ConsumerState<OrderDetailsPage> {
  bool _isLoading = true;
  bool _isCancelling = false;
  bool _isReordering = false;
  bool _isSubmittingReview = false;
  bool _isProcessingReconciliation = false;
  bool _isCallingSupport = false;
  bool _autoOpenedRevisionSheet = false;
  OrderModel? _order;
  VendorModel? _vendor;
  InvoiceResult? _invoice;
  OtpResult? _otp;
  bool _otpPaymentPending = false;
  OrderReconciliationModel? _reconciliation;
  bool? _hasReviewed;

  static const List<String> _cancelReasons = [
    'I need to reschedule',
    'Picked a different vendor',
    'Changed my mind',
    'Estimated cost too high',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _loadOrderDetails();
  }

  Future<void> _loadOrderDetails() async {
    setState(() => _isLoading = true);
    final repo = ref.read(customerRepositoryProvider);
    try {
      final o = await repo.getOrderById(widget.orderId);
      VendorModel? v;
      if (o.vendorId.isNotEmpty) {
        try {
          v = await repo.getVendorById(o.vendorId);
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _order = o;
          _vendor = v;
          _isLoading = false;
          _invoice = null;
          _otp = null;
          _otpPaymentPending = false;
          _hasReviewed = null;
          _reconciliation = null;
        });
        unawaited(_maybeFetchInvoice(o));
        unawaited(_maybeFetchOtp(o));
        unawaited(_maybeFetchReviewStatus(o));
        unawaited(_maybeFetchReconciliation(o));
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _maybeFetchReviewStatus(OrderModel order) async {
    if (order.status != OrderStatus.delivered &&
        order.status != OrderStatus.deliveryOtpVerified) {
      return;
    }
    try {
      final reviewed = await ref
          .read(customerRepositoryProvider)
          .hasReviewedOrder(widget.orderId);
      if (mounted) setState(() => _hasReviewed = reviewed);
    } catch (_) {}
  }

  Future<void> _maybeFetchReconciliation(OrderModel order) async {
    if (order.status != OrderStatus.reconciliationPending) return;
    try {
      final reconciliation = await ref
          .read(customerRepositoryProvider)
          .getOrderReconciliation(widget.orderId);
      if (mounted) {
        setState(() => _reconciliation = reconciliation);
        if (reconciliation != null &&
            !_autoOpenedRevisionSheet &&
            order.status == OrderStatus.reconciliationPending) {
          _autoOpenedRevisionSheet = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => _showRevisionSheet());
        }
      }
    } catch (_) {}
  }

  Future<void> _showRevisionSheet() async {
    final reconciliation = _reconciliation;
    final order = _order;
    if (reconciliation == null || order == null || !mounted) return;

    final decision = await OrderRevisionSheet.show(
      context: context,
      reconciliation: reconciliation,
      order: order,
    );
    if (decision == null || !mounted) return;

    setState(() => _isProcessingReconciliation = true);
    try {
      final repo = ref.read(customerRepositoryProvider);
      if (decision == ReconciliationDecision.accept) {
        await repo.acceptOrderReconciliation(widget.orderId);
        if (mounted) AppSnackBar.showSuccess(context, 'New total accepted — processing continues.');
      } else {
        await repo.rejectOrderReconciliation(widget.orderId);
        if (mounted) {
          AppSnackBar.showInfo(context, 'We\'ve flagged this for support to call you.');
        }
      }
      await _loadOrderDetails();
    } catch (e) {
      if (mounted) AppSnackBar.showError(context, 'Failed to submit your decision: $e');
    } finally {
      if (mounted) setState(() => _isProcessingReconciliation = false);
    }
  }

  Future<void> _callSupport() async {
    setState(() => _isCallingSupport = true);
    try {
      final contact = await ref.read(customerRepositoryProvider).getSupportContact();
      final phone = contact.phone;
      if (phone == null || phone.isEmpty) {
        if (mounted) AppSnackBar.showError(context, 'Support phone number is unavailable right now.');
        return;
      }
      final uri = Uri(scheme: 'tel', path: phone);
      final launched = await launchUrl(uri);
      if (!launched && mounted) {
        AppSnackBar.showError(context, 'Could not open the dialer.');
      }
    } catch (e) {
      if (mounted) AppSnackBar.showError(context, 'Failed to fetch support contact: $e');
    } finally {
      if (mounted) setState(() => _isCallingSupport = false);
    }
  }

  Future<void> _maybeFetchInvoice(OrderModel order) async {
    if (order.status != OrderStatus.delivered &&
        order.status != OrderStatus.deliveryOtpVerified) {
      return;
    }
    try {
      final invoice = await ref
          .read(customerRepositoryProvider)
          .getOrderInvoice(widget.orderId);
      if (mounted) setState(() => _invoice = invoice);
    } catch (_) {}
  }

  Future<void> _maybeFetchOtp(OrderModel order) async {
    if (!order.status.showPickupOtpHint && !order.status.showDeliveryOtpHint) {
      return;
    }
    final purpose = order.status.showDeliveryOtpHint ? 'DELIVERY' : 'PICKUP';
    try {
      final otp = await ref
          .read(customerRepositoryProvider)
          .getOrderOtp(widget.orderId, purpose: purpose);
      if (mounted) setState(() => _otp = otp);
    } on ApiException catch (e) {
      if (purpose == 'DELIVERY' && e.code == 'PAYMENT_PENDING' && mounted) {
        setState(() => _otpPaymentPending = true);
      }
    } catch (_) {}
  }

  Future<void> _showCancelSheet() async {
    String? selectedReason;

    await AppBottomSheet.show<String>(
      context: context,
      title: 'Cancel Order',
      primaryActionLabel: 'Confirm Cancellation',
      onPrimaryAction: () {
        if (selectedReason != null && selectedReason!.isNotEmpty) {
          // See order_revision_sheet.dart for why this must target the
          // root navigator explicitly — this page is a nested route
          // inside the Orders tab's own Navigator, not the one
          // AppBottomSheet.show (useRootNavigator: true) actually used.
          Navigator.of(context, rootNavigator: true).pop(selectedReason);
        }
      },
      child: StatefulBuilder(
        builder: (ctx, setModalState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Please select a reason for cancelling:',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            Gap(AppSpacing.md.h),
            ..._cancelReasons.map((r) => Padding(
                  padding: EdgeInsets.only(bottom: 8.h),
                  child: AppCard.outlined(
                    borderColor: selectedReason == r
                        ? AppColors.error
                        : AppColors.outline,
                    backgroundColor: selectedReason == r        ? AppColors.error.withValues(alpha: 0.08)
        : AppColors.transparent,
                    onTap: () => setModalState(() => selectedReason = r),
                    child: Text(r, style: AppTypography.bodyMedium),
                  ),
                )),
          ],
        ),
      ),
    ).then((reason) {
      if (reason != null && reason.isNotEmpty && mounted) {
        _executeCancel(reason);
      }
    });
  }

  Future<void> _executeCancel(String reason) async {
    setState(() => _isCancelling = true);
    try {
      final repo = ref.read(customerRepositoryProvider);
      final updated = await repo.cancelOrder(widget.orderId, reason: reason);
      if (mounted) {
        setState(() {
          _order = updated;
          _isCancelling = false;
        });
        AppSnackBar.showSuccess(context, 'Order cancelled successfully');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCancelling = false);
        AppSnackBar.showError(context, 'Failed to cancel: ${e.toString()}');
      }
    }
  }

  Future<void> _handleReorder() async {
    setState(() => _isReordering = true);
    try {
      final repo = ref.read(customerRepositoryProvider);
      final result = await repo.reorder(widget.orderId);
      if (mounted) {
        setState(() => _isReordering = false);
        AppSnackBar.showSuccess(context, result.message);
        context.go(AppRoutes.cart);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isReordering = false);
        AppSnackBar.showError(context, 'Reorder failed: ${e.toString()}');
      }
    }
  }

  Future<void> _handleDownloadInvoice() async {
    if (_invoice?.pdfBytes != null && _invoice!.pdfBytes!.isNotEmpty) {
      final file = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}${_invoice!.fileName ?? 'invoice-${widget.orderId}.pdf'}',
      );
      await file.writeAsBytes(_invoice!.pdfBytes!, flush: true);
      final launched = await launchUrl(
        Uri.file(file.path),
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        AppSnackBar.showInfo(context, 'Invoice downloaded to ${file.path}');
      }
      return;
    }
    if (_invoice?.pdfUrl != null) {
      final uri = Uri.tryParse(_invoice!.pdfUrl!);
      if (uri != null && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  Future<void> _showReviewSheet(OrderModel order) async {
    var vendorRating = 5;
    var riderRating = 5;
    final commentController = TextEditingController();

    final shouldSubmit = await AppBottomSheet.show<bool>(
      context: context,
      title: 'Review Order',
      primaryActionLabel: 'Submit Review',
      onPrimaryAction: () =>
          Navigator.of(context, rootNavigator: true).pop(true),
      isScrollControlled: true,
      child: StatefulBuilder(
        builder: (context, setModalState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Vendor rating', style: AppTypography.labelMedium),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                5,
                (index) => IconButton(
                  icon: Icon(
                    index < vendorRating
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: AppColors.warning,
                  ),
                  onPressed: () =>
                      setModalState(() => vendorRating = index + 1),
                ),
              ),
            ),
            Text('Delivery rating', style: AppTypography.labelMedium),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                5,
                (index) => IconButton(
                  icon: Icon(
                    index < riderRating
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: AppColors.warning,
                  ),
                  onPressed: () => setModalState(() => riderRating = index + 1),
                ),
              ),
            ),
            AppTextField(
              label: 'Comment',
              hint: 'Share your experience',
              controller: commentController,
              maxLines: 3,
              borderRadius: AppRadius.sm,
            ),
          ],
        ),
      ),
    );

    if (shouldSubmit != true) {
      commentController.dispose();
      return;
    }

    setState(() => _isSubmittingReview = true);
    try {
      await ref.read(customerRepositoryProvider).createReview(
            orderId: order.id,
            vendorRating: vendorRating,
            riderRating: riderRating,
            comment: commentController.text.trim().isEmpty
                ? null
                : commentController.text.trim(),
          );
      if (mounted) {
        setState(() => _hasReviewed = true);
        AppSnackBar.showSuccess(context, 'Review submitted.');
      }
    } catch (e) {
      if (mounted) AppSnackBar.showError(context, e.toString());
    } finally {
      commentController.dispose();
      if (mounted) setState(() => _isSubmittingReview = false);
    }
  }

  // Canonical customer-visible forward-progress timeline per spec §4/§6.
  static const List<OrderStatus> _timelineSteps = [
    OrderStatus.waitingForVendorConfirmation,
    OrderStatus.vendorAccepted,
    OrderStatus.goingForPickup,
    OrderStatus.pickedUp,
    OrderStatus.receivedAtVendor,
    OrderStatus.processing,
    OrderStatus.packed,
    OrderStatus.outForDelivery,
    OrderStatus.delivered,
  ];

  /// Maps every canonical order status to its row index in [_timelineSteps].
  /// `_timelineSteps` only lists the 9 customer-visible milestones, but the
  /// backend's status enum has intermediate states (e.g. PICKUP_ASSIGNED
  /// between vendor-accepted and going-for-pickup, PICKUP_OTP_VERIFIED
  /// between going-for-pickup and picked-up) that never appear verbatim in
  /// that list — looking those up with `indexOf` returned -1 and made the
  /// whole timeline render as "nothing completed yet" for orders sitting in
  /// one of those states, even mid-flow ones like a vendor-confirmed order.
  int _timelineStepIndex(OrderStatus status) => switch (status) {
        OrderStatus.waitingForVendorConfirmation => 0,
        OrderStatus.vendorAccepted || OrderStatus.pickupAssigned => 1,
        OrderStatus.goingForPickup => 2,
        OrderStatus.pickupOtpVerified || OrderStatus.pickedUp => 3,
        OrderStatus.receivedAtVendor ||
        OrderStatus.reconciliationPending ||
        OrderStatus.reconciliationDisputed =>
          4,
        OrderStatus.processing => 5,
        OrderStatus.packed => 6,
        OrderStatus.deliveryAssigned || OrderStatus.outForDelivery => 7,
        OrderStatus.deliveryOtpVerified || OrderStatus.delivered => 8,
        _ => -1,
      };

  String _shortId(String id) => id.length > 8
      ? id.substring(id.length - 8).toUpperCase()
      : id.toUpperCase();

  Color _statusColor(OrderStatus s) {
    if (s.isRejected || s == OrderStatus.paymentFailed || s == OrderStatus.reconciliationDisputed) {
      return AppColors.error;
    }
    if (s == OrderStatus.delivered || s == OrderStatus.deliveryOtpVerified) {
      return AppColors.success;
    }
    if (s.hasRefundState || s == OrderStatus.reconciliationPending) {
      return AppColors.warning;
    }
    return AppColors.primary;
  }

  String _stepDescription(OrderStatus s) => switch (s) {
        OrderStatus.waitingForVendorConfirmation =>
          'Order sent to vendor; awaiting acceptance.',
        OrderStatus.vendorAccepted =>
          'Vendor confirmed. Pickup being arranged.',
        OrderStatus.goingForPickup =>
          'Pickup partner is on the way to your address.',
        OrderStatus.pickedUp =>
          'Garments collected and heading to the partner.',
        OrderStatus.receivedAtVendor =>
          'Arrived at laundry. Quantities being confirmed.',
        OrderStatus.processing =>
          'Clothes are being washed, dried and/or ironed.',
        OrderStatus.packed => 'Packed and ready. Delivery being arranged.',
        OrderStatus.outForDelivery => 'On the way to your delivery address.',
        OrderStatus.delivered => 'Delivered. Thank you for choosing LNDRY!',
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final isDark = theme.brightness == Brightness.dark;

    // Live sync: a socket event for THIS order (vendor accepted/rejected
    // it, or proposed a reconciliation) reloads the page in place instead
    // of the customer needing to pull-to-refresh or reopen the app — see
    // OrderSyncListener, which publishes this provider.
    ref.listen<OrderSyncEvent?>(orderSyncEventProvider, (previous, next) {
      if (next != null && next.orderId == widget.orderId && !_isLoading) {
        _loadOrderDetails();
      }
    });

    if (_isLoading) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(backgroundColor: AppColors.transparent, elevation: 0),
        body: const AppLoadingPage(message: 'Loading order details...'),
      );
    }

    if (_order == null) {
      return Scaffold(
        body: AppErrorWidget.fullscreen(
          title: 'Order Not Found',
          message: 'We couldn\'t load details for order #${widget.orderId}.',
          onRetry: _loadOrderDetails,
        ),
      );
    }

    final order = _order!;
    final isRejected = order.status.isRejected;
    final isCancelled = order.status == OrderStatus.customerCancelled ||
        order.status == OrderStatus.adminCancelled;
    final currentStepIdx = _timelineStepIndex(order.status);

    // Whichever of the rider's/vendor's re-evaluation happened most
    // recently, so the customer sees who touched their order last without
    // having to scroll to both sections to compare timestamps.
    final rider = order.riderReevaluation;
    final vendor = order.vendorReevaluation;
    String? latestEvaluatorLabel;
    if (rider != null || vendor != null) {
      final riderTime = rider?.createdAt;
      final vendorTime = vendor?.createdAt;
      final vendorIsLatest = vendorTime != null &&
          (riderTime == null || vendorTime.isAfter(riderTime));
      latestEvaluatorLabel = vendorIsLatest
          ? 'Vendor Re-evaluation (Final)'
          : 'Captain Re-evaluation (Preliminary)';
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
            'Order #${order.orderNumber.isNotEmpty ? order.orderNumber : _shortId(order.id)}',
            style: AppTypography.titleLarge),
        centerTitle: true,          leading: IconButton(
            icon: const Icon(AppIcons.back),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go(AppRoutes.orders);
              }
            },
          ),
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.surface,
        elevation: 0,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadOrderDetails,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(AppSpacing.pagePaddingH.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Current status ─────────────────────────────────────────
                Center(
                  child: StatusBadge(
                    label: order.status.label,
                    color: _statusColor(order.status),
                    large: true,
                  ),
                ),
                if (order.source == 'STORE') ...[
                  Gap(AppSpacing.xs.h),
                  const Center(
                    child: StatusBadge(
                      label: 'Laundry Store',
                      color: AppColors.tertiary,
                    ),
                  ),
                ],
                if (latestEvaluatorLabel != null) ...[
                  Gap(AppSpacing.xs.h),
                  Center(
                    child: Text(
                      'Latest update: $latestEvaluatorLabel',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                Gap(AppSpacing.sectionGap.h),

                // ── Schedule banner ─────────────────────────────────────────
                // Shown at the very top, independent of whether the vendor
                // lookup below succeeds, so the customer always sees which
                // pickup slot they chose at checkout without having to hunt
                // for it inside the timeline (which never showed it at all).
                if (order.scheduledPickupAt != null) ...[
                  AppCard.outlined(
                    backgroundColor: AppColors.primaryContainer,
                    borderColor: AppColors.primary.withValues(alpha: 0.2),
                    child: Row(
                      children: [
                        Icon(
                          order.isExpressPickup
                              ? Icons.bolt_rounded
                              : AppIcons.calendar,
                          color: AppColors.primary,
                          size: 22.r,
                        ),
                        Gap(AppSpacing.cardGap.h),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Your Pickup Schedule',
                                style: AppTypography.labelSmall.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Gap(2.h),
                              Text(
                                order.pickupSummary,
                                style: AppTypography.titleSmall.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Gap(AppSpacing.md.h),
                ],

                // ── Vendor info with pickup/delivery estimates ─────────────
                if (_vendor != null) ...[
                  AppCard.outlined(
                    backgroundColor: isDark
                        ? AppColors.darkSurfaceContainer
                        : AppColors.surface,
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(10.r),
                          decoration: const BoxDecoration(
                            color: AppColors.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(AppIcons.store,
                              color: AppColors.primary, size: 24.r),
                        ),
                        Gap(AppSpacing.cardGap.h),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_vendor!.name,
                                  style: AppTypography.titleSmall
                                      .copyWith(fontWeight: FontWeight.bold)),
                              if (order.scheduledPickupAt != null)
                                Text(
                                  'Pickup: ${order.pickupSummary}',
                                  style: AppTypography.bodySmall
                                      .copyWith(color: AppColors.textSecondary),
                                ),
                              if (order.estimatedDeliveryAt != null)
                                Text(
                                  'Delivery: ${order.estimatedDeliveryAt!.toDateTimeString}',
                                  style: AppTypography.bodySmall
                                      .copyWith(color: AppColors.textSecondary),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Gap(AppSpacing.md.h),
                ],

                // ── Payment status ──────────────────────────────────────────
                PaymentStatusCard(order: order),
                Gap(AppSpacing.md.h),

                // ── Balance due (payable once the final evaluation is done) ──
                if ([
                  OrderStatus.processing,
                  OrderStatus.packed,
                  OrderStatus.deliveryAssigned,
                  OrderStatus.outForDelivery,
                  OrderStatus.deliveryOtpVerified,
                  OrderStatus.delivered,
                ].contains(order.status)) ...[
                  BalancePaymentCard(order: order, onPaid: _loadOrderDetails),
                  Gap(AppSpacing.md.h),
                ],

                // ── Rejection/cancellation banner ─────────────────────────
                if (isRejected) ...[
                  _Banner(
                    icon: AppIcons.error,
                    color: AppColors.error,
                    title: order.status.label,
                    body: order.vendorRejectionReason ??
                        (order.status == OrderStatus.autoRejected
                            ? 'The vendor did not respond in time.'
                            : 'The vendor was unable to accept your order.'),
                  ),
                  Gap(AppSpacing.md.h),
                ] else if (isCancelled) ...[
                  _Banner(
                    icon: AppIcons.close,
                    color: AppColors.error,
                    title: 'Order Cancelled',
                    body: order.cancellationReason ??
                        'This order has been cancelled.',
                  ),
                  Gap(AppSpacing.md.h),
                ] else if (order.status == OrderStatus.reconciliationPending) ...[
                  _Banner(
                    icon: Icons.hourglass_top_rounded,
                    color: AppColors.warning,
                    title: 'Your order total was updated',
                    body: 'The vendor found a difference after weighing your items. Review it to continue processing.',
                  ),
                  Gap(AppSpacing.cardGap.h),
                  AppButton(
                    label: 'Review Updated Total',
                    isLoading: _isProcessingReconciliation,
                    isDisabled: _isProcessingReconciliation || _reconciliation == null,
                    onPressed: _showRevisionSheet,
                  ),
                  Gap(AppSpacing.md.h),
                ] else if (order.status == OrderStatus.reconciliationDisputed) ...[
                  _Banner(
                    icon: AppIcons.error,
                    color: AppColors.error,
                    title: 'Order total disputed',
                    body: 'You rejected the vendor\'s revised total. Our support team will call you to resolve this.',
                  ),
                  Gap(AppSpacing.cardGap.h),
                  AppButton.outlined(
                    label: 'Call Support',
                    icon: const Icon(Icons.call_rounded, size: 18),
                    isLoading: _isCallingSupport,
                    isDisabled: _isCallingSupport,
                    onPressed: _callSupport,
                  ),
                  Gap(AppSpacing.md.h),
                ],

                // ── Timeline ───────────────────────────────────────────────
                if (!isRejected && !isCancelled) ...[
                  Text('Order Timeline', style: AppTypography.titleMedium),
                  Gap(AppSpacing.cardGap.h),
                  AppCard.outlined(
                    padding:
                        EdgeInsets.symmetric(horizontal: 20.w, vertical: 24.h),
                    child: ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _timelineSteps.length,
                      itemBuilder: (context, idx) {
                        final step = _timelineSteps[idx];
                        final isCompleted =
                            currentStepIdx >= 0 && idx <= currentStepIdx;
                        final isCurrent = idx == currentStepIdx;
                        final showLine = idx < _timelineSteps.length - 1;

                        return IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Column(
                                children: [
                                  Container(
                                    width: 16.r,
                                    height: 16.r,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isCompleted
                                          ? AppColors.primary
                                          : AppColors.outline.withValues(alpha: 0.5),
                                      border: isCurrent
                                          ? Border.all(
                                              color: AppColors.primaryContainer,
                                              width: 3.r)
                                          : null,
                                    ),
                                    child: isCompleted
                                        ? Icon(Icons.check,
                                            size: 10.r, color: AppColors.white)
                                        : null,
                                  ),
                                  if (showLine)
                                    Expanded(
                                      child: Container(
                                        width: 2.w,
                                        color: isCompleted
                                            ? AppColors.primary
                                            : AppColors.outline
                                                .withValues(alpha: 0.4),
                                      ),
                                    ),
                                ],
                              ),
                              Gap(AppSpacing.cardGap.h),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 20),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        step.label,
                                        style:
                                            AppTypography.labelLarge.copyWith(
                                          color: isCompleted
                                              ? AppColors.textBlack
                                              : AppColors.onSurfaceVariant,
                                          fontWeight: isCurrent
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                      Text(
                                        _stepDescription(step),
                                        style: AppTypography.bodySmall.copyWith(
                                          color: AppColors.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Gap(AppSpacing.sectionGap.h),
                ],

                // ── Rider / Vendor Re-evaluation sections ───────────────
                // Rider's correction is a preliminary, at-pickup estimate;
                // the vendor's is the authoritative, final one — shown
                // explicitly since a customer may see both across the same
                // order and needs to know which one actually determines
                // what they pay.
                if (rider != null) ...[
                  _ReevaluationSection(
                    title: 'Captain Re-evaluation',
                    subtitle: 'Preliminary estimate at pickup — not final',
                    reconciliation: rider,
                    order: order,
                  ),
                  Gap(AppSpacing.md.h),
                ],
                if (vendor != null) ...[
                  _ReevaluationSection(
                    title: 'Vendor Re-evaluation',
                    subtitle: 'Final — confirmed after vendor inspection',
                    reconciliation: vendor,
                    order: order,
                  ),
                  Gap(AppSpacing.md.h),
                ],

                // ── Order items ─────────────────────────────────────────
                if (order.items.isNotEmpty) ...[
                  Text('Items', style: AppTypography.titleMedium),
                  Gap(AppSpacing.cardGap.h),
                  _ReevaluationStatusFlow(
                    riderDone: rider != null,
                    pickupDone: _isPickupDone(order.status),
                    vendorDone: vendor != null,
                  ),
                  Gap(AppSpacing.md.h),
                  AppCard.outlined(
                    padding: EdgeInsets.all(AppSpacing.md.r),
                    child: Column(
                      children: order.items
                          .map((item) => Padding(
                                padding: EdgeInsets.symmetric(vertical: 6.h),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${_itemQuantityLabel(item)} × ${item.serviceName}',
                                        style: AppTypography.bodyMedium,
                                      ),
                                    ),
                                    if (item.totalPrice > 0)
                                      Text(
                                        item.totalPrice.toCurrencyDecimal,
                                        style: AppTypography.labelLarge
                                            .copyWith(
                                                fontWeight: FontWeight.bold),
                                      ),
                                  ],
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                  Gap(AppSpacing.md.h),
                ],

                // ── Pricing summary ─────────────────────────────────────
                if (order.total > 0) ...[
                  PriceCard(
                    subtotal: order.subtotal,
                    // Handling fee is already baked into `total` by the
                    // backend alongside the platform fee — folded into one
                    // row here rather than listed separately.
                    platformFee: order.platformFee + order.handlingFee,
                    gstAmount: order.gstAmount,
                    total: order.total,
                    deliveryFee: order.deliveryFee,
                    amountPaid: order.amountPaid,
                    statusText: vendor != null
                        ? 'Vendor Re-evaluation Done'
                        : (rider != null ? 'Captain Re-evaluation Done' : null),
                    isFinalBill: vendor != null,
                  ),
                  Gap(AppSpacing.sectionGap.h),
                ],

                // ── OTP Section (Pickup or Delivery) ────────────────────
                if (_otp != null) ...[
                  Text('Security OTP', style: AppTypography.titleMedium),
                  Gap(AppSpacing.cardGap.h),
                  AppCard.outlined(
                    backgroundColor:
                        AppColors.primaryContainer.withValues(alpha: 0.15),
                    borderColor: AppColors.primary.withValues(alpha: 0.3),
                    padding: EdgeInsets.all(AppSpacing.md.r),
                    child: Column(
                      children: [
                        Icon(
                          _otp!.type == 'pickup'
                              ? Icons.pin_rounded
                              : Icons.verified_user_rounded,
                          color: AppColors.primary,
                          size: 32.r,
                        ),
                        Gap(AppSpacing.sm.h),
                        Text(
                          _otp!.type == 'pickup'
                              ? 'Pickup OTP'
                              : 'Delivery OTP',
                          style: AppTypography.labelMedium.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Gap(AppSpacing.sm.h),
                        Text(
                          'Provide this code to the partner:',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                        Gap(AppSpacing.cardGap.h),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 24.w,
                            vertical: 12.h,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius:
                                BorderRadius.circular(AppRadius.input.r),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Text(
                            _otp!.otp,
                            style: AppTypography.headlineSmall.copyWith(
                              letterSpacing: 8,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        Gap(AppSpacing.sm.h),
                        Text(
                          'Expires at ${_otp!.expiresAt.toTimeString}',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.warning,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Gap(AppSpacing.sectionGap.h),
                ] else if (_otpPaymentPending) ...[
                  Text('Security OTP', style: AppTypography.titleMedium),
                  Gap(AppSpacing.cardGap.h),
                  AppCard.outlined(
                    backgroundColor: AppColors.warning.withValues(alpha: 0.08),
                    borderColor: AppColors.warning.withValues(alpha: 0.3),
                    padding: EdgeInsets.all(AppSpacing.md.r),
                    child: Column(
                      children: [
                        Icon(Icons.lock_outline_rounded, color: AppColors.warning, size: 32.r),
                        Gap(AppSpacing.sm.h),
                        Text(
                          'Delivery OTP Locked',
                          style: AppTypography.labelMedium.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Gap(AppSpacing.cardGap.h),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(AppRadius.input.r),
                            border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            '• • • • • •',
                            style: AppTypography.headlineSmall.copyWith(
                              letterSpacing: 8,
                              fontWeight: FontWeight.bold,
                              color: AppColors.warning,
                            ),
                          ),
                        ),
                        Gap(AppSpacing.sm.h),
                        Text(
                          'Complete the remaining payment to unlock your Delivery OTP.',
                          textAlign: TextAlign.center,
                          style: AppTypography.caption.copyWith(color: AppColors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Gap(AppSpacing.sectionGap.h),
                ],

                // ── Invoice Section (Delivered orders) ──────────────────
                if (_invoice != null) ...[
                  Text('Invoice', style: AppTypography.titleMedium),
                  Gap(AppSpacing.cardGap.h),
                  AppCard.outlined(
                    onTap: _handleDownloadInvoice,
                    padding: EdgeInsets.all(AppSpacing.md.r),
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(10.r),
                          decoration: const BoxDecoration(
                            color: AppColors.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            AppIcons.document,
                            color: AppColors.primary,
                            size: 24.r,
                          ),
                        ),
                        Gap(AppSpacing.cardGap.h),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Invoice #${_invoice!.id.length >= 8 ? _invoice!.id.substring(_invoice!.id.length - 8).toUpperCase() : _invoice!.id.toUpperCase()}',
                                style: AppTypography.labelLarge.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (_invoice!.total > 0)
                                Text(
                                  'Total: ${_invoice!.total.toCurrencyDecimal}',
                                  style: AppTypography.bodySmall.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                )
                              else
                                Text(
                                  'PDF invoice ready',
                                  style: AppTypography.bodySmall.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Icon(
                          AppIcons.download,
                          color: AppColors.primary,
                          size: 20.r,
                        ),
                      ],
                    ),
                  ),
                  Gap(AppSpacing.sectionGap.h),
                ],

                // ── Action buttons (Cancel / Reorder) ───────────────────
                Row(
                  children: [
                    // Cancel button (when cancellable)
                    if (order.status.isCancellable)
                      Expanded(
                        child: AppButton.outlined(
                          label: 'Cancel Order',
                          icon: const Icon(AppIcons.close, size: 18),
                          foregroundColor: AppColors.error,
                          isLoading: _isCancelling,
                          isDisabled: _isCancelling,
                          onPressed: _showCancelSheet,
                        ),
                      ),
                    if (order.status.isCancellable) Gap(AppSpacing.cardGap.h),
                    // Reorder button (terminal orders except customer/admin-cancelled)
                    if (order.status.isTerminal &&
                        order.status != OrderStatus.customerCancelled &&
                        order.status != OrderStatus.adminCancelled)
                      Expanded(
                        child: AppButton(
                          label: 'Reorder',
                          icon: const Icon(Icons.repeat_rounded, size: 18),
                          isLoading: _isReordering,
                          isDisabled: _isReordering,
                          onPressed: _handleReorder,
                        ),
                      ),
                    if ((order.status == OrderStatus.delivered ||
                            order.status == OrderStatus.deliveryOtpVerified) &&
                        !_isSubmittingReview) ...[
                      if (order.status.isTerminal &&
                          order.status != OrderStatus.customerCancelled &&
                          order.status != OrderStatus.adminCancelled)
                        Gap(AppSpacing.cardGap.h),
                      Expanded(
                        child: _hasReviewed == true
                            ? AppButton.outlined(
                                label: 'Reviewed',
                                icon: const Icon(Icons.star_rounded, size: 18),
                                isDisabled: true,
                                onPressed: () {},
                              )
                            : AppButton.outlined(
                                label: 'Review',
                                icon: const Icon(Icons.star_border_rounded, size: 18),
                                isLoading: _isSubmittingReview,
                                isDisabled: _isSubmittingReview,
                                onPressed: () => _showReviewSheet(order),
                              ),
                      ),
                    ],
                  ],
                ),
                Gap(AppSpacing.sectionGap.h),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Re-evaluation section ──────────────────────────────────────────────────

/// Persistent, always-visible record of a rider's or vendor's re-evaluation
/// — distinct from [OrderRevisionSheet], which is the transient
/// accept/reject prompt shown only while a vendor proposal is pending.
/// This section stays in order details permanently once either evaluation
/// has happened, showing previous vs. updated items/quantities/amount, who
/// performed it, and its status.
class _ReevaluationSection extends StatelessWidget {
  const _ReevaluationSection({
    required this.title,
    required this.subtitle,
    required this.reconciliation,
    required this.order,
  });

  final String title;
  final String subtitle;
  final OrderReconciliationModel reconciliation;
  final OrderModel order;

  /// Which item a reported problem is about — an existing line's name
  /// comes from the order's own items; a line the vendor added during this
  /// same reconciliation (no real order_lines.id yet at submission time)
  /// comes from the reconciliation's own line_changes, matched by position
  /// among its is-new entries.
  String? _itemNameFor(ReconciliationProblem problem) {
    if (problem.orderLineId != null) {
      for (final item in order.items) {
        if (item.orderLineId == problem.orderLineId) return item.serviceName;
      }
      return null;
    }
    if (problem.newLineIndex != null) {
      final newLineChanges =
          reconciliation.lineChanges.where((c) => c.isNew).toList();
      if (problem.newLineIndex! >= 0 &&
          problem.newLineIndex! < newLineChanges.length) {
        return newLineChanges[problem.newLineIndex!].proposedName;
      }
    }
    return null;
  }

  String get _performedBy => switch (reconciliation.proposedByRole) {
        'VENDOR_RIDER' => 'Captain',
        'VENDOR_OWNER' || 'VENDOR_STAFF' => 'Vendor',
        _ => reconciliation.proposedByRole ?? 'Unknown',
      };

  (String, Color) get _statusInfo => switch (reconciliation.status) {
        'APPLIED' => ('Applied', AppColors.success),
        'PENDING_CUSTOMER' => ('Waiting for your approval', AppColors.warning),
        'ACCEPTED' => ('Accepted', AppColors.success),
        'REJECTED' => ('Rejected — disputed', AppColors.error),
        _ => (reconciliation.status, AppColors.onSurfaceVariant),
      };

  @override
  Widget build(BuildContext context) {
    final previousAmount = reconciliation.previousPayableAmountPaise / 100.0;
    final updatedAmount = reconciliation.proposedPayableAmountPaise / 100.0;
    final (statusLabel, statusColor) = _statusInfo;
    final isVendorFinal = title.startsWith('Vendor') && reconciliation.status == 'ACCEPTED';

    return AppCard.outlined(
      padding: EdgeInsets.all(AppSpacing.md.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.bold)),
              ),
              StatusBadge(label: statusLabel, color: statusColor),
            ],
          ),
          Gap(2.h),
          Text(
            subtitle,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
          Gap(AppSpacing.xs.h),
          Text(
            'Performed by: $_performedBy',
            style: AppTypography.bodySmall.copyWith(color: AppColors.onSurfaceVariant),
          ),
          Gap(AppSpacing.cardGap.h),

          if (reconciliation.lineChanges.isNotEmpty) ...[
            Text('Items', style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.bold)),
            Gap(4.h),
            ...reconciliation.lineChanges.map((c) => Padding(
                  padding: EdgeInsets.symmetric(vertical: 2.h),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.isReclassified
                              ? '${c.previousName ?? 'Item'} → ${c.proposedName ?? 'Item'}'
                              : (c.proposedName ?? c.previousName ?? 'Item'),
                          style: AppTypography.bodySmall,
                        ),
                      ),
                      Text(
                        '${c.previousQuantity}${_unitSuffix(c.previousUnit)} → ${c.proposedQuantity}${_unitSuffix(c.proposedUnit)}',
                        style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                )),
            Gap(AppSpacing.cardGap.h),
          ],

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Previous amount', style: AppTypography.bodySmall.copyWith(color: AppColors.onSurfaceVariant)),
              Text(previousAmount.toCurrencyDecimal, style: AppTypography.bodySmall),
            ],
          ),
          Gap(2.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Updated amount', style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold)),
              Text(
                updatedAmount.toCurrencyDecimal,
                style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold, color: AppColors.primary),
              ),
            ],
          ),

          if (isVendorFinal) ...[
            Gap(AppSpacing.cardGap.h),
            Text(
              'This is the vendor\'s final evaluated amount.',
              style: AppTypography.bodySmall.copyWith(color: AppColors.success, fontWeight: FontWeight.w600),
            ),
          ],

          // Structured per-item reports — exactly which service had an
          // issue, why, and that item's own photo evidence. Distinct from
          // the general reason/photos below, which aren't tied to any one
          // line and predate this per-item reporting.
          if (reconciliation.problems.isNotEmpty) ...[
            Gap(AppSpacing.cardGap.h),
            Text('Reported Issues', style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.bold)),
            Gap(6.h),
            for (final problem in reconciliation.problems)
              Container(
                margin: EdgeInsets.only(bottom: 8.h),
                padding: EdgeInsets.all(10.r),
                decoration: BoxDecoration(
                  color: AppColors.black,
                  borderRadius: BorderRadius.circular(AppRadius.sm.r),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      problem.displayReason('Other'),
                      style: AppTypography.bodySmall.copyWith(color: AppColors.white, fontWeight: FontWeight.bold),
                    ),
                    if (_itemNameFor(problem) case final itemName?) ...[
                      Gap(2.h),
                      Text(
                        'For: $itemName',
                        style: AppTypography.bodySmall.copyWith(color: AppColors.white.withOpacity(0.75)),
                      ),
                    ],
                    if (problem.photoUrls.isNotEmpty) ...[
                      Gap(6.h),
                      SizedBox(
                        height: 52.r,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: problem.photoUrls.length,
                          separatorBuilder: (_, __) => Gap(6.w),
                          itemBuilder: (context, idx) => ClipRRect(
                            borderRadius: BorderRadius.circular(6.r),
                            child: Image.network(
                              problem.photoUrls[idx],
                              width: 52.r,
                              height: 52.r,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],

          if (reconciliation.photos.isNotEmpty) ...[
            Gap(AppSpacing.cardGap.h),
            SizedBox(
              height: 64.r,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: reconciliation.photos.length,
                separatorBuilder: (_, __) => Gap(8.w),
                itemBuilder: (context, idx) => ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm.r),
                  child: Image.network(
                    reconciliation.photos[idx],
                    width: 64.r,
                    height: 64.r,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Re-evaluation status flow ─────────────────────────────────────────────────

/// Compact at-a-glance progress strip shown at the top of the Items section:
/// Rider Re-evaluation (Pending/Done) -> Pickup (Done) -> Vendor
/// Re-evaluation (Pending/Done), plus a "final bill" callout once the
/// vendor's re-evaluation is in. Deliberately separate from
/// [_ReevaluationSection] below, which shows the full previous/updated item
/// diff — this is just the quick status a customer glances at first.
class _ReevaluationStatusFlow extends StatelessWidget {
  const _ReevaluationStatusFlow({
    required this.riderDone,
    required this.pickupDone,
    required this.vendorDone,
  });

  final bool riderDone;
  final bool pickupDone;
  final bool vendorDone;

  @override
  Widget build(BuildContext context) {
    return AppCard.outlined(
      padding: EdgeInsets.all(AppSpacing.md.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _flowStep('Captain Re-evaluation', riderDone),
          Gap(6.h),
          _flowStep('Pickup', pickupDone),
          Gap(6.h),
          _flowStep('Vendor Re-evaluation', vendorDone),
          if (vendorDone) ...[
            Gap(AppSpacing.cardGap.h),
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.sm.r),
              ),
              child: Text(
                'This is your final bill',
                textAlign: TextAlign.center,
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.success,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _flowStep(String label, bool done) {
    final color = done ? AppColors.success : AppColors.warning;
    return Row(
      children: [
        Icon(
          done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
          size: 16.r,
          color: color,
        ),
        Gap(8.w),
        Expanded(
          child: Text(label, style: AppTypography.bodySmall),
        ),
        Text(
          done ? 'Done' : 'Pending',
          style: AppTypography.bodySmall.copyWith(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

// ── Banner widget ─────────────────────────────────────────────────────────────

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(AppSpacing.md.r),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.card.r),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20.r),
          Gap(AppSpacing.cardGap.h),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppTypography.labelLarge
                        .copyWith(color: color, fontWeight: FontWeight.bold)),
                Gap(AppSpacing.xs.h),
                Text(body,
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
