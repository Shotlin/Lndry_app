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
