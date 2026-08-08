import 'package:razorpay_flutter/razorpay_flutter.dart';

/// Wraps a single Razorpay checkout's gateway-event wiring (open/success/
/// failure/external-wallet) plus success-event idempotency — Razorpay can
/// redeliver the same success event more than once on a flaky connection,
/// so callers only ever see it once per [open] call.
///
/// Shared by the checkout [PaymentPage] (advance) and `BalancePaymentCard`
/// (balance-at-delivery) so this lifecycle/dedupe logic isn't duplicated
/// between the two places a Razorpay checkout can be opened from.
class RazorpayPaymentController {
  RazorpayPaymentController({
    required this.onSuccess,
    required this.onFailure,
    this.onExternalWallet,
  }) {
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onFailure);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
  }

  late final Razorpay _razorpay;
  final void Function(PaymentSuccessResponse response) onSuccess;
  final void Function(PaymentFailureResponse response) onFailure;
  final void Function(ExternalWalletResponse response)? onExternalWallet;
  final Set<String> _handledEvents = <String>{};

  /// Opens the Razorpay checkout sheet with [options]. Clears the
  /// per-attempt dedupe set so a retried payment isn't blocked by a
  /// previous attempt's event key.
  void open(Map<String, dynamic> options) {
    _handledEvents.clear();
    _razorpay.open(options);
  }

  void _onSuccess(PaymentSuccessResponse response) {
    final eventKey = response.paymentId ?? response.orderId ?? '';
    if (eventKey.isNotEmpty && !_handledEvents.add(eventKey)) return;
    onSuccess(response);
  }

  void _onFailure(PaymentFailureResponse response) {
    _handledEvents.clear();
    onFailure(response);
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    onExternalWallet?.call(response);
  }

  /// Releases the underlying Razorpay instance. Must be called from the
  /// owning widget's `dispose()`.
  void dispose() {
    _razorpay.clear();
  }
}
