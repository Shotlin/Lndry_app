import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/socket_service.dart';

final socketServiceProvider = Provider<SocketService>((ref) {
  final service = SocketService();
  ref.onDispose(service.disconnect);
  return service;
});

/// A just-received `order:status`/`notification` socket event for one
/// order — published by [OrderSyncListener] so a currently-open
/// `OrderDetailsPage` for the same order can reload itself in place
/// instead of waiting for the next pull-to-refresh.
class OrderSyncEvent {
  const OrderSyncEvent({required this.orderId, required this.receivedAt});

  final String orderId;
  final DateTime receivedAt;
}

final orderSyncEventProvider = StateProvider<OrderSyncEvent?>((ref) => null);

/// A `notification` event's title/body, for a one-shot in-app popup.
/// Cleared immediately after [OrderSyncListener] shows it so it isn't
/// replayed on the next rebuild.
class OrderNotificationEvent {
  const OrderNotificationEvent({required this.title, required this.body});

  final String title;
  final String body;
}

final orderNotificationEventProvider =
    StateProvider<OrderNotificationEvent?>((ref) => null);
