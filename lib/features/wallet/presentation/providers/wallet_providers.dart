import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../providers/auth_provider.dart';
import '../../../../repositories/repositories.dart';

/// Current LNDRY wallet balance — used both by the My Wallet page and by
/// Checkout's "Pay with Wallet" option.
final walletProvider = FutureProvider<WalletModel>((ref) {
  if (ref.watch(authProvider) is! AuthAuthenticated) {
    return Future.value(const WalletModel(id: '', balance: 0));
  }
  final repo = ref.watch(customerRepositoryProvider);
  return repo.getWallet();
});

/// Wallet transaction history, most recent first — My Wallet page only.
final walletTransactionsProvider =
    FutureProvider<List<WalletTransactionModel>>((ref) {
  if (ref.watch(authProvider) is! AuthAuthenticated) return Future.value([]);
  final repo = ref.watch(customerRepositoryProvider);
  return repo.getWalletTransactions();
});

/// A vendor's own POS counter proposing to redeem part of this wallet's
/// balance against an in-person sale, if one is currently pending — shown
/// as a banner at the top of My Wallet. Null when there's nothing pending.
/// Refreshed on pull-to-refresh, on a live 'WALLET_REDEMPTION_REQUESTED'
/// socket notification (see order_sync_listener.dart), and on app resume
/// via the page's own re-fetch.
final pendingWalletRedemptionProvider =
    FutureProvider<PendingWalletRedemption?>((ref) {
  if (ref.watch(authProvider) is! AuthAuthenticated) return Future.value(null);
  final repo = ref.watch(customerRepositoryProvider);
  return repo.getPendingWalletRedemption();
});
