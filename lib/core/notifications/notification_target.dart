/// Screens a push notification is allowed to open in the customer app.
///
/// The backend resolves every notification to a concrete route, but the app
/// never trusts a payload: only routes matching this whitelist are opened, so a
/// crafted or corrupted notification can never navigate anywhere unexpected.
abstract final class NotificationRoutes {
  static const _exact = <String>{
    '/home',
    '/orders',
    '/vendors',
    '/search',
    '/cart',
    '/profile',
    '/profile/offers',
    '/profile/wallet',
    '/profile/notifications',
    '/profile/help',
    '/profile/refer-earn',
    '/profile/settings',
    '/profile/address',
    '/profile/reviews',
    '/profile/edit',
  };

  static final _patterns = <RegExp>[
    RegExp(r'^/orders/details/[A-Za-z0-9_-]{1,64}$'),
    RegExp(r'^/vendor/[A-Za-z0-9_-]{1,64}$'),
  ];

  static const fallback = '/profile/notifications';

  static bool isAllowed(String route) =>
      _exact.contains(route) || _patterns.any((p) => p.hasMatch(route));

  /// The route for a logical link (`type` + params), or null if it has none.
  static String? forLink(String type, Map<String, String> params) {
    switch (type) {
      case 'home':
        return '/home';
      case 'orders':
        return '/orders';
      case 'order_details':
      case 'order_tracking':
      case 'order_approval':
      case 'order_payment':
      case 'order_review':
      case 'rider_job':
        final id = params['orderId'];
        return (id == null || id.isEmpty) ? '/orders' : '/orders/details/$id';
      case 'vendor_details':
        final id = params['vendorId'];
        return (id == null || id.isEmpty) ? '/vendors' : '/vendor/$id';
      case 'offers':
        return '/profile/offers';
      case 'wallet':
        return '/profile/wallet';
      case 'refer_earn':
        return '/profile/refer-earn';
      case 'notifications':
        return '/profile/notifications';
      case 'help':
        return '/profile/help';
      case 'profile':
        return '/profile';
      case 'route':
        return params['route'];
      default:
        return null;
    }
  }
}

/// What a tapped notification asks the app to do.
class NotificationTarget {
  const NotificationTarget({
    required this.type,
    required this.route,
    this.deliveryId,
    this.notificationId,
    this.campaignId,
    this.messageId,
  });

  /// Logical destination (`order_details`, `wallet`, `none`, …).
  final String type;

  /// A whitelisted in-app route, or null when the notification only opens the app.
  final String? route;

  final String? deliveryId;
  final String? notificationId;
  final String? campaignId;
  final String? messageId;

  /// Identifies one delivered message, so a tap is handled exactly once even if
  /// the system hands the same message to the app twice.
  String get dedupeKey =>
      deliveryId ?? messageId ?? notificationId ?? '$type|${route ?? ''}';

  bool get hasReportableId =>
      deliveryId != null || notificationId != null || campaignId != null;

  /// Parses an FCM `data` map. Returns null when the message is not one of
  /// ours (no destination fields at all), so unrelated pushes are ignored.
  static NotificationTarget? fromData(
    Map<String, dynamic> data, {
    String? messageId,
  }) {
    String? s(String key) {
      final v = data[key];
      if (v == null) return null;
      final text = v.toString().trim();
      return text.isEmpty ? null : text;
    }

    final type = s('type');
    final deepLink = s('deepLink');
    if (type == null && deepLink == null && s('deliveryId') == null) {
      return null;
    }

    final params = <String, String>{
      for (final k in const ['orderId', 'vendorId'])
        if (s(k) != null) k: s(k)!,
    };

    // Prefer the route the backend resolved; otherwise derive it locally.
    var route = deepLink ?? NotificationRoutes.forLink(type ?? 'none', params);
    if (route != null && !NotificationRoutes.isAllowed(route)) {
      route = NotificationRoutes.fallback;
    }

    return NotificationTarget(
      type: type ?? 'none',
      route: route,
      deliveryId: s('deliveryId'),
      notificationId: s('notificationId'),
      campaignId: s('campaignId'),
      messageId: messageId ?? s('messageId'),
    );
  }

  /// A destination that came from inside the app (e.g. an inbox item).
  static NotificationTarget? forRoute(String? route) {
    if (route == null || route.isEmpty) return null;
    final safe =
        NotificationRoutes.isAllowed(route) ? route : NotificationRoutes.fallback;
    return NotificationTarget(type: 'route', route: safe);
  }
}
