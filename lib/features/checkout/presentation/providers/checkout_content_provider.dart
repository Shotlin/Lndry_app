import '../../../../core/design/design_system.dart';
import '../../../../repositories/repositories.dart';

/// Admin-editable payment-screen messages. Re-fetched every time the payment
/// screen opens (autoDispose), so a dashboard edit shows up on the next
/// checkout with no app update. If the request fails the built-in text is
/// used, so the screen is never left without its messages.
final checkoutContentProvider =
    FutureProvider.autoDispose<CheckoutContent>((ref) async {
  try {
    return await ref.read(customerRepositoryProvider).getCheckoutContent();
  } catch (_) {
    return CheckoutContent.fallback;
  }
});
