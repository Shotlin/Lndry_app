import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lndry/core/services/storage_service.dart';
import 'package:lndry/features/orders/presentation/pages/order_details_page.dart';
import 'package:lndry/models/models.dart';
import 'package:lndry/providers/auth_provider.dart';
import 'package:lndry/repositories/repositories.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// The order-details call button: whose number it dials changes with the
/// order's lifecycle, but always comes from real backend/order data — never
/// a second hardcoded number.

class _FakeLauncher extends UrlLauncherPlatform with MockPlatformInterfaceMixin {
  final launched = <String>[];
  @override
  LinkDelegate? get linkDelegate => null;
  @override
  Future<bool> canLaunch(String url) async => true;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

class _TestStorage extends StorageService {
  _TestStorage({required super.prefs});
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

class _SignedIn extends AuthNotifier {
  _SignedIn(super.repo, super.storage);
  void signIn() => state = const AuthAuthenticated(
        UserModel(id: 'u1', phone: '9999999999', name: 'Test', role: UserRole.customer),
      );
}

class _Repo extends MockCustomerRepository {
  _Repo(this.order, {this.supportPhone = '18001234567', this.supportShouldThrow = false});
  final OrderModel order;
  final String? supportPhone;
  final bool supportShouldThrow;
  int supportCalls = 0;

  @override
  Future<OrderModel> getOrderById(String orderId) async => order;

  @override
  Future<StoreOrderDetail?> findStoreOrder(String id) async => null;

  @override
  Future<VendorModel> getVendorById(String vendorId) async => throw Exception('n/a');

  @override
  Future<SupportContact> getSupportContact() async {
    supportCalls++;
    if (supportShouldThrow) throw Exception('should never be called');
    return SupportContact(phone: supportPhone, email: 'help@lndry.in');
  }
}

OrderModel _order({
  required OrderStatus status,
  String? pickupCaptainPhone,
  String? deliveryCaptainPhone,
}) =>
    OrderModel(
      id: 'o1',
      orderNumber: 'LNDR-20260923-XYZ',
      customerId: 'u1',
      vendorId: '',
      items: const [],
      status: status,
      total: 100,
      pickupCaptainPhone: pickupCaptainPhone,
      deliveryCaptainPhone: deliveryCaptainPhone,
      createdAt: DateTime(2026, 9, 23),
    );

Future<Widget> _app(WidgetTester tester, _Repo repo) async {
  SharedPreferences.setMockInitialValues({'fresh_install_reset_done_v3': true});
  final storage = _TestStorage(prefs: await SharedPreferences.getInstance());
  final auth = _SignedIn(repo, storage);
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  auth.signIn();

  final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (_, __) => const OrderDetailsPage(orderId: 'o1'))],
  );
  return ProviderScope(
    overrides: [
      customerRepositoryProvider.overrideWithValue(repo),
      storageServiceProvider.overrideWithValue(storage),
      authProvider.overrideWith((ref) => auth),
    ],
    child: ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      builder: (_, __) => MaterialApp.router(routerConfig: router),
    ),
  );
}

Future<void> _settle(WidgetTester tester, {int ms = 4000}) async {
  for (var waited = 0; waited < ms; waited += 100) {
    await tester.pump(const Duration(milliseconds: 100));
    while (tester.takeException() != null) {}
  }
}

void main() {
  late _FakeLauncher launcher;
  setUp(() {
    launcher = _FakeLauncher();
    UrlLauncherPlatform.instance = launcher;
  });

  Future<void> tapCallButton(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.call_rounded));
    await tester.pumpAndSettle();
  }

  group('lifecycle stages that must show LNDRY support', () {
    for (final status in [
      OrderStatus.waitingForVendorConfirmation,
      OrderStatus.vendorAccepted,
      OrderStatus.pickedUp,
      OrderStatus.receivedAtVendor,
      OrderStatus.processing,
      OrderStatus.packed,
      OrderStatus.delivered,
    ]) {
      testWidgets('$status dials the platform support number, never a captain', (tester) async {
        // Captain numbers are present but must be ignored at this stage.
        final repo = _Repo(_order(
          status: status,
          pickupCaptainPhone: '9000000002',
          deliveryCaptainPhone: '9000000003',
        ));
        await tester.pumpWidget(await _app(tester, repo));
        await _settle(tester);

        await tapCallButton(tester);
        expect(repo.supportCalls, 1);
        expect(launcher.launched, ['tel:18001234567']);
      });
    }
  });

  group('pickup captain window', () {
    for (final status in [OrderStatus.pickupAssigned, OrderStatus.goingForPickup, OrderStatus.pickupOtpVerified]) {
      testWidgets('$status dials the assigned pickup captain directly, no support lookup at all', (tester) async {
        final repo = _Repo(_order(status: status, pickupCaptainPhone: '9000000002'));
        await tester.pumpWidget(await _app(tester, repo));
        await _settle(tester);

        await tapCallButton(tester);
        expect(launcher.launched, ['tel:9000000002']);
        expect(repo.supportCalls, 0, reason: 'the captain number came straight from the order, no network call needed');
      });
    }

    testWidgets('falls back to support when no pickup captain number is available yet', (tester) async {
      final repo = _Repo(_order(status: OrderStatus.goingForPickup, pickupCaptainPhone: null));
      await tester.pumpWidget(await _app(tester, repo));
      await _settle(tester);

      await tapCallButton(tester);
      expect(launcher.launched, ['tel:18001234567']);
    });
  });

  group('delivery captain window', () {
    for (final status in [OrderStatus.deliveryAssigned, OrderStatus.outForDelivery, OrderStatus.deliveryOtpVerified]) {
      testWidgets('$status dials the assigned delivery captain directly', (tester) async {
        final repo = _Repo(_order(status: status, deliveryCaptainPhone: '9000000003'));
        await tester.pumpWidget(await _app(tester, repo));
        await _settle(tester);

        await tapCallButton(tester);
        expect(launcher.launched, ['tel:9000000003']);
        expect(repo.supportCalls, 0);
      });
    }

    testWidgets('never shows the pickup captain during the delivery window', (tester) async {
      final repo = _Repo(_order(
        status: OrderStatus.outForDelivery,
        pickupCaptainPhone: '9000000002',
        deliveryCaptainPhone: '9000000003',
      ));
      await tester.pumpWidget(await _app(tester, repo));
      await _settle(tester);

      await tapCallButton(tester);
      expect(launcher.launched, ['tel:9000000003']);
    });
  });

  testWidgets('a clean message shows if the support number itself is unavailable', (tester) async {
    final repo = _Repo(_order(status: OrderStatus.waitingForVendorConfirmation), supportPhone: null);
    await tester.pumpWidget(await _app(tester, repo));
    await _settle(tester);

    await tapCallButton(tester);
    expect(launcher.launched, isEmpty);
    expect(find.textContaining('Support phone number is unavailable'), findsOneWidget);
  });
}
