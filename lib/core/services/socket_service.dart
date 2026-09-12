import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../config/env.dart';

/// Thin wrapper around the Socket.IO client, connecting to the same
/// backend server (`socketio.plugin.js`) Lndry_vendor_app's rider-side
/// socket already uses — mirrors that app's `socket_service.dart`.
///
/// Without this, an order's status change (vendor accept/reject, a
/// reconciliation proposal) only ever reached the customer app the next
/// time a screen happened to refetch (pull-to-refresh or app restart),
/// since `activeOrdersProvider`/`pastOrdersProvider` are plain one-shot
/// FutureProviders with no live invalidation trigger. This connects the
/// moment the customer is authenticated so `order:status`/`notification`
/// events (see `socketio.plugin.js`'s `emitOrderUpdate`/`emitNotification`,
/// already emitted from `acceptOrder`/`rejectOrder`/`proposeReconciliation`)
/// can invalidate those providers live — see `OrderSyncListener`.
class SocketService {
  io.Socket? _socket;

  bool get isConnected => _socket?.connected ?? false;

  void connect({
    required String token,
    required void Function(Map<String, dynamic> data) onOrderStatus,
    required void Function(Map<String, dynamic> data) onNotification,
  }) {
    if (_socket != null) return;

    _socket = io.io(
      Env.socketBaseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .disableAutoConnect()
          .build(),
    );

    _socket!
      ..onConnect((_) => debugPrint('[Socket] connected'))
      ..onConnectError((err) => debugPrint('[Socket] connect error: $err'))
      ..onError((err) => debugPrint('[Socket] error: $err'))
      ..onDisconnect((_) => debugPrint('[Socket] disconnected'))
      ..on('order:status', (data) {
        if (data is Map) onOrderStatus(Map<String, dynamic>.from(data));
      })
      ..on('notification', (data) {
        if (data is Map) onNotification(Map<String, dynamic>.from(data));
      })
      ..connect();
  }

  void disconnect() {
    _socket?.clearListeners();
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }
}
