import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../providers/auth_provider.dart';
import '../../../../repositories/repositories.dart';

/// Coupons the current customer can currently use, for the Coupons & Offers
/// page. The backend already filters to targeting-eligible ones.
final availableCouponsProvider = FutureProvider<List<CouponSummary>>((ref) {
  if (ref.watch(authProvider) is! AuthAuthenticated) return Future.value([]);
  final repo = ref.watch(customerRepositoryProvider);
  return repo.getAvailableCoupons();
});

/// Whether the current customer still qualifies for a first-order offer.
final firstTimeOfferProvider = FutureProvider<FirstTimeOfferResult>((ref) {
  if (ref.watch(authProvider) is! AuthAuthenticated) {
    return Future.value(const FirstTimeOfferResult(eligible: false));
  }
  final repo = ref.watch(customerRepositoryProvider);
  return repo.getActiveFirstTimeOffer();
});

/// A coupon code the customer chose to apply from the Coupons & Offers page,
/// picked up by whichever of Cart/Checkout is opened next (there's no
/// single shared "current order" screen the Offers page could apply it to
/// directly — those two pages independently own their own coupon-field
/// state). Cleared the moment it's consumed.
final pendingCouponCodeProvider = StateProvider<String?>((ref) => null);
