import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../providers/auth_provider.dart';
import '../../../../repositories/repositories.dart';

/// The current customer's own referral code, stats, and active program
/// terms — the "Refer & Earn" screen's hero + stats-strip data.
final referralSummaryProvider = FutureProvider<ReferralSummary>((ref) {
  if (ref.watch(authProvider) is! AuthAuthenticated) {
    return Future.value(const ReferralSummary(
      referralCode: null,
      totalReferred: 0,
      pending: 0,
      completed: 0,
      totalWalletEarned: 0,
    ));
  }
  final repo = ref.watch(customerRepositoryProvider);
  return repo.getReferralSummary();
});

/// Every person referred so far, most recent first — the timeline list.
final referralHistoryProvider = FutureProvider<List<ReferralHistoryItem>>((ref) {
  if (ref.watch(authProvider) is! AuthAuthenticated) return Future.value([]);
  final repo = ref.watch(customerRepositoryProvider);
  return repo.getReferralHistory();
});
