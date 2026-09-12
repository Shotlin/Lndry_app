import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/home/presentation/providers/home_providers.dart';
import '../../providers/auth_provider.dart';
import '../../providers/order_sync_provider.dart';
import '../constants/app_constants.dart';
import '../services/storage_service.dart';
import 'app_snackbar.dart';

/// Wraps the whole app (see main.dart's `MaterialApp.router` builder) to
/// connect a Socket.IO session the moment the customer is authenticated —
/// mirrors Lndry_vendor_app's `JobOfferListener`.
///
/// Without this, a vendor accepting/rejecting an order or proposing a
/// reconciliation only ever reached the customer app's
/// `activeOrdersProvider`/`pastOrdersProvider` (plain one-shot
/// FutureProviders, no live invalidation) and `OrderDetailsPage`'s
/// imperative `_loadOrderDetails()` the NEXT time either happened to
/// refetch — pull-to-refresh, or a full app close/reopen. Never live,
/// even while the customer was already looking at the order.
///
/// On every `order:status` or `notification` event (see
/// `socketio.plugin.js`'s `emitOrderUpdate`/`emitNotification`, already
/// emitted from `acceptOrder`/`rejectOrder`/`proposeReconciliation`):
///   - invalidates `activeOrdersProvider`/`pastOrdersProvider`, so the
///     Orders list and Home screen silently refetch wherever they're
///     currently watched, no manual pull-to-refresh needed;
///   - publishes the event's `orderId` via [orderSyncEventProvider] so an
///     already-open `OrderDetailsPage` for that same order reloads itself
///     in place (see that page's `build()`).
/// A `notification` event additionally shows a one-shot SnackBar using the
/// backend's own title/body (already human-authored server-side).
class OrderSyncListener extends ConsumerStatefulWidget {
  const OrderSyncListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<OrderSyncListener> createState() => _OrderSyncListenerState();
}

class _OrderSyncListenerState extends ConsumerState<OrderSyncListener> {
  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authProvider, (previous, next) {
      _syncSocket(next);
    });

    ref.listen<OrderNotificationEvent?>(orderNotificationEventProvider,
        (previous, next) {
      if (next == null) return;
      AppSnackBar.showInfo(context, '${next.title}\n${next.body}');
      // Clear right after showing so a rebuild (e.g. theme change) doesn't
      // replay the same popup.
      Future.microtask(() {
        if (mounted) {
          ref.read(orderNotificationEventProvider.notifier).state = null;
        }
      });
    });

    return widget.child;
  }

  Future<void> _syncSocket(AuthState state) async {
    final socket = ref.read(socketServiceProvider);
    if (state is AuthAuthenticated) {
      final storage = ref.read(storageServiceProvider);
      final token = await storage.getSecure(AppConstants.keyAccessToken);
      if (token != null && token.isNotEmpty) {
        socket.connect(
          token: token,
          onOrderStatus: _handleOrderEvent,
          onNotification: (data) {
            _handleOrderEvent(data);
            final title = data['title'] as String? ?? 'Order update';
            final body = data['body'] as String? ?? '';
            ref.read(orderNotificationEventProvider.notifier).state =
                OrderNotificationEvent(title: title, body: body);
          },
        );
      }
    } else {
      socket.disconnect();
    }
  }

  void _handleOrderEvent(Map<String, dynamic> data) {
    ref.invalidate(activeOrdersProvider);
    ref.invalidate(pastOrdersProvider);

    final nested = data['data'];
    final orderId = data['orderId'] as String? ??
        (nested is Map ? nested['orderId'] as String? : null);
    if (orderId != null && orderId.isNotEmpty) {
      ref.read(orderSyncEventProvider.notifier).state =
          OrderSyncEvent(orderId: orderId, receivedAt: DateTime.now());
    }
  }
}
