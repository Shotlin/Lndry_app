import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lndry/core/notifications/notification_router.dart';
import 'package:lndry/core/notifications/notification_target.dart';
import 'package:lndry/core/services/storage_service.dart';
import 'package:lndry/models/models.dart';
import 'package:lndry/providers/auth_provider.dart';
import 'package:lndry/repositories/repositories.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Repo extends MockCustomerRepository {
  final List<Map<String, String?>> opened = [];

  @override
  Future<void> reportNotificationOpened({
    String? deliveryId,
    String? notificationId,
    String? campaignId,
  }) async {
    opened.add({'delivery': deliveryId, 'notification': notificationId, 'campaign': campaignId});
  }
}

class _Storage extends StorageService {
  _Storage({required super.prefs});
  final Map<String, String> _secure = {};
  @override
  Future<void> saveSecure(String key, String value) async => _secure[key] = value;
  @override
  Future<String?> getSecure(String key) async => _secure[key];
  @override
  Future<void> deleteSecure(String key) async => _secure.remove(key);
  @override
  Future<void> deleteAllSecure() async => _secure.clear();
  @override
  Future<Map<String, String>> getAllSecure() async => Map.of(_secure);
}

class _Auth extends AuthNotifier {
  _Auth(super.repo, super.storage);
  void set(AuthState s) => state = s;
}

const _user = UserModel(id: 'u1', name: 'Sayan', phone: '9999999999', role: UserRole.customer);

Map<String, dynamic> _orderTap(String id, {String delivery = 'd1'}) => {
      'type': 'order_details',
      'deepLink': '/orders/details/$id',
      'orderId': id,
      'deliveryId': delivery,
      'notificationId': 'n1',
    };

void main() {
  group('NotificationTarget', () {
    test('opens the resolved route and carries the ids for tap tracking', () {
      final t = NotificationTarget.fromData(_orderTap('abc'), messageId: 'm1')!;
      expect(t.type, 'order_details');
      expect(t.route, '/orders/details/abc');
      expect((t.deliveryId, t.notificationId, t.messageId), ('d1', 'n1', 'm1'));
    });

    test('derives the route when only a logical type is present', () {
      expect(NotificationTarget.fromData({'type': 'wallet'})!.route, '/profile/wallet');
      expect(NotificationTarget.fromData({'type': 'order_details', 'orderId': 'x9'})!.route, '/orders/details/x9');
      expect(NotificationTarget.fromData({'type': 'order_details'})!.route, '/orders');
    });

    test('every order-screen link type opens that exact order', () {
      for (final type in ['order_details', 'order_tracking', 'order_approval', 'order_payment', 'order_review']) {
        final t = NotificationTarget.fromData({'type': type, 'orderId': 'ord-7'})!;
        expect(t.route, '/orders/details/ord-7', reason: type);
      }
    });

    test('never opens a route outside the whitelist', () {
      for (final bad in ['https://evil.example', '/admin', '/orders/details/../../x', '//x', '/profile/wallet?x=1']) {
        final t = NotificationTarget.fromData({'type': 'route', 'deepLink': bad})!;
        expect(t.route, '/profile/notifications', reason: bad);
      }
    });

    test('ignores pushes that are not ours and "open the app" pushes have no route', () {
      expect(NotificationTarget.fromData({'foo': 'bar'}), isNull);
      expect(NotificationTarget.fromData({'type': 'none', 'deepLink': '', 'deliveryId': 'd'})!.route, isNull);
    });
  });

  group('NotificationRouter', () {
    late _Repo repo;
    late _Auth auth;
    late GoRouter router;
    late ProviderContainer container;
    late NotificationRouter nr;
    final visited = <String>[];

    Future<void> setUpRouter(WidgetTester tester, {String initial = '/home'}) async {
      SharedPreferences.setMockInitialValues({});
      final storage = _Storage(prefs: await SharedPreferences.getInstance());
      repo = _Repo();
      auth = _Auth(repo, storage);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      visited.clear();
      router = GoRouter(initialLocation: initial, routes: [
        GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('SPLASH'))),
        GoRoute(path: '/home', builder: (_, __) => const Scaffold(body: Text('HOME'))),
        GoRoute(path: '/orders/details/:id', builder: (_, s) { visited.add(s.uri.path); return Scaffold(body: Text('ORDER ${s.pathParameters['id']}')); }),
        GoRoute(path: '/profile/notifications', builder: (_, __) => const Scaffold(body: Text('INBOX'))),
        GoRoute(path: '/login', builder: (_, s) => Scaffold(body: Text('LOGIN ${s.uri.queryParameters['returnTo']}'))),
      ]);
      container = ProviderContainer(overrides: [
        customerRepositoryProvider.overrideWithValue(repo),
        storageServiceProvider.overrideWithValue(storage),
        authProvider.overrideWith((ref) => auth),
      ]);
      addTearDown(container.dispose);
      nr = container.read(notificationRouterProvider)..attachForTest(router);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('signed in: tap opens the order on top of home and reports the open', (tester) async {
      await setUpRouter(tester);
      auth.set(const AuthAuthenticated(_user));
      nr.tapForTest(_orderTap('abc'));
      await tester.pumpAndSettle();
      expect(find.text('ORDER abc'), findsOneWidget);
      expect(repo.opened, [{'delivery': 'd1', 'notification': 'n1', 'campaign': null}]);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget, reason: 'Back returns to where the user was');
    });

    testWidgets('signed out: goes to sign-in carrying the destination, and reports after sign-in', (tester) async {
      await setUpRouter(tester);
      auth.set(const AuthUnauthenticated());
      nr.tapForTest(_orderTap('abc'));
      await tester.pumpAndSettle();
      expect(find.text('LOGIN /orders/details/abc'), findsOneWidget);
      expect(repo.opened, isEmpty, reason: 'cannot report before signing in');
      auth.set(const AuthAuthenticated(_user));
      nr.tryConsume();
      expect(repo.opened.length, 1);
    });

    testWidgets('killed-app launch: waits out the splash, then opens the destination', (tester) async {
      await setUpRouter(tester, initial: '/');
      auth.set(const AuthAuthenticated(_user));
      nr.tapForTest(_orderTap('abc'));
      await tester.pumpAndSettle();
      expect(find.text('SPLASH'), findsOneWidget, reason: 'not swallowed by the splash');
      router.go('/home');
      await tester.pumpAndSettle();
      expect(find.text('ORDER abc'), findsOneWidget);
    });

    testWidgets('waits for the session to be restored before deciding', (tester) async {
      await setUpRouter(tester);
      auth.set(const AuthLoading());
      nr.tapForTest(_orderTap('abc'));
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
      auth.set(const AuthAuthenticated(_user));
      nr.tryConsume();
      await tester.pumpAndSettle();
      expect(find.text('ORDER abc'), findsOneWidget);
    });

    testWidgets('the same message is handled once, even if the OS delivers it twice', (tester) async {
      await setUpRouter(tester);
      auth.set(const AuthAuthenticated(_user));
      nr.tapForTest(_orderTap('abc'), messageId: 'm1');
      await tester.pumpAndSettle();
      router.pop();
      await tester.pumpAndSettle();
      nr.tapForTest(_orderTap('abc'), messageId: 'm1');
      await tester.pumpAndSettle();
      expect(visited.length, 1);
      expect(repo.opened.length, 1);
    });

    testWidgets('a crafted route falls back to the notification list', (tester) async {
      await setUpRouter(tester);
      auth.set(const AuthAuthenticated(_user));
      nr.tapForTest({'type': 'route', 'deepLink': 'https://evil.example', 'deliveryId': 'd2'});
      await tester.pumpAndSettle();
      expect(find.text('INBOX'), findsOneWidget);
    });

    testWidgets('an in-app inbox tap uses the same path', (tester) async {
      await setUpRouter(tester);
      auth.set(const AuthAuthenticated(_user));
      nr.openRoute('/orders/details/zz');
      await tester.pumpAndSettle();
      expect(find.text('ORDER zz'), findsOneWidget);
    });
  });
}
