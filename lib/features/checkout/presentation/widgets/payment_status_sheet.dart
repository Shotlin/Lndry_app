import 'dart:async';

import '../../../../core/theme/theme.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../repositories/repositories.dart';

/// Shown when a payment is not yet confirmed: the customer's bank can take
/// minutes (sometimes an hour) to settle a UPI / net-banking debit. Rather than
/// declaring a failure — which makes people pay twice — this waits honestly,
/// polling the server (which asks the payment gateway), and closes with the
/// final answer as soon as there is one.
///
/// Pops with the last [PaymentStatusResult], or null if the customer chose to
/// stop waiting.
class PaymentStatusSheet extends ConsumerStatefulWidget {
  const PaymentStatusSheet({
    required this.orderDraftId,
    super.key,
    this.maxWait = const Duration(minutes: 3),
    this.pollEvery = const Duration(seconds: 4),
  });

  final String orderDraftId;
  final Duration maxWait;
  final Duration pollEvery;

  static Future<PaymentStatusResult?> show(
    BuildContext context, {
    required String orderDraftId,
  }) {
    return showModalBottomSheet<PaymentStatusResult?>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      useRootNavigator: true,
      builder: (_) => PaymentStatusSheet(orderDraftId: orderDraftId),
    );
  }

  @override
  ConsumerState<PaymentStatusSheet> createState() => _PaymentStatusSheetState();
}

class _PaymentStatusSheetState extends ConsumerState<PaymentStatusSheet> {
  Timer? _timer;
  late final DateTime _startedAt;
  bool _checking = false;
  bool _timedOut = false;
  String _message =
      'Waiting for your bank to confirm the payment. Please do not pay again.';

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _timer = Timer.periodic(widget.pollEvery, (_) => _check());
    unawaited(_check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (_checking || !mounted) return;
    _checking = true;
    try {
      final status = await ref
          .read(customerRepositoryProvider)
          .getPaymentStatus(orderDraftId: widget.orderDraftId)
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (status.isFinal) {
        _timer?.cancel();
        Navigator.of(context, rootNavigator: true).pop(status);
        return;
      }
      setState(() {
        if (status.message != null && status.message!.isNotEmpty) {
          _message = status.message!;
        }
      });
    } catch (_) {
      // A dropped connection must not look like a failed payment; keep waiting.
    } finally {
      _checking = false;
      if (mounted &&
          !_timedOut &&
          DateTime.now().difference(_startedAt) > widget.maxWait) {
        _timer?.cancel();
        setState(() => _timedOut = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.pagePaddingH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_timedOut)
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(strokeWidth: 3),
              )
            else
              const Icon(Icons.hourglass_bottom_rounded,
                  size: 36, color: AppColors.primary),
            const Gap(16),
            Text(
              _timedOut ? 'Still confirming your payment' : 'Confirming your payment',
              style: AppTypography.titleMedium,
              textAlign: TextAlign.center,
            ),
            const Gap(8),
            Text(
              _timedOut
                  ? 'Some banks take a while. If money was deducted, your booking '
                      'will be confirmed automatically and you will get a '
                      'notification — you do not need to pay again. You can '
                      'safely leave this screen.'
                  : _message,
              style:
                  AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const Gap(20),
            if (_timedOut) ...[
              AppButton(
                label: 'Check again',
                onPressed: () {
                  setState(() => _timedOut = false);
                  _timer = Timer.periodic(widget.pollEvery, (_) => _check());
                  unawaited(_check());
                },
              ),
              const Gap(10),
              AppButton.secondary(
                label: 'Go to My Orders',
                onPressed: () => Navigator.of(context, rootNavigator: true).pop(null),
              ),
            ] else
              TextButton(
                onPressed: _check,
                child: const Text('Check now'),
              ),
          ],
        ),
      ),
    );
  }
}
