import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lndry/core/services/storage_service.dart';
import 'package:lndry/features/orders/presentation/pages/order_details_page.dart';
import 'package:lndry/features/vendor_details/presentation/pages/vendor_details_page.dart';
import 'package:lndry/models/models.dart';
import 'package:lndry/providers/auth_provider.dart';
import 'package:lndry/repositories/repositories.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Records what the app asks the OS to open (same fake used by
/// test/invoice_flow_test.dart for the same reason).
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

// A real network call from `Image.network` fails deterministically in the
// test environment (no internet) with a 400 — replace it with a tiny valid
// PNG so every evidence thumbnail actually decodes and paints, the same as
// it would on a real device with a real evidence photo.
final _kTransparentPng = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

class _FakeHttpHeaders extends Fake implements HttpHeaders {
  @override
  void forEach(void Function(String name, List<String> values) action) {}
}

class _FakeHttpClientResponse extends Fake implements HttpClientResponse {
  @override
  int get statusCode => 200;
  @override
  int get contentLength => _kTransparentPng.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  HttpHeaders get headers => _FakeHttpHeaders();
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([_kTransparentPng]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

class _FakeHttpClientRequest extends Fake implements HttpClientRequest {
  @override
  HttpHeaders get headers => _FakeHttpHeaders();
  @override
  Future<HttpClientResponse> close() async => _FakeHttpClientResponse();
}

class _FakeHttpClient extends Fake implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeHttpClientRequest();
}

class _FakeHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeHttpClient();
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

Future<Widget> _app(WidgetTester tester, CustomerRepository repo, Widget home) async {
  SharedPreferences.setMockInitialValues({'fresh_install_reset_done_v3': true});
  final storage = _TestStorage(prefs: await SharedPreferences.getInstance());
  final auth = _SignedIn(repo, storage);
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  auth.signIn();

  final router = GoRouter(routes: [GoRoute(path: '/', builder: (_, __) => home)]);
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

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

// ── Full-screen re-evaluation image viewer ──────────────────────────────────

class _OrderRepo extends MockCustomerRepository {
  _OrderRepo(this.order);
  final OrderModel order;

  @override
  Future<OrderModel> getOrderById(String orderId) async => order;

  @override
  Future<StoreOrderDetail?> findStoreOrder(String id) async => null;

  @override
  Future<VendorModel> getVendorById(String vendorId) async => throw Exception('n/a');
}

OrderModel _orderWithEvidence() => OrderModel(
      id: 'o1',
      orderNumber: 'LNDR-20260923-ABC',
      customerId: 'u1',
      vendorId: '',
      items: const [
        OrderItem(serviceId: 's1', serviceName: 'Shirt', quantity: 2, unitPrice: 50, totalPrice: 100, orderLineId: 'l1'),
      ],
      status: OrderStatus.processing,
      total: 100,
      createdAt: DateTime(2026, 9, 23),
      vendorReevaluation: OrderReconciliationModel(
        id: 'r1',
        orderId: 'o1',
        stage: 'VENDOR_RECEIPT',
        status: 'ACCEPTED',
        previousPayableAmountPaise: 10000,
        proposedPayableAmountPaise: 12000,
        photos: const ['https://example.com/evidence1.jpg', 'https://example.com/evidence2.jpg'],
        proposedByRole: 'VENDOR_OWNER',
      ),
    );

void main() {
  setUpAll(() => HttpOverrides.global = _FakeHttpOverrides());

  group('re-evaluation evidence — full-screen viewer', () {
    testWidgets('tapping a thumbnail opens a full-screen zoomable viewer with a close button', (tester) async {
      _tall(tester);
      await tester.pumpWidget(await _app(tester, _OrderRepo(_orderWithEvidence()), const OrderDetailsPage(orderId: 'o1')));
      await _settle(tester);

      // The order screen itself is showing (not navigated away from yet).
      expect(find.textContaining('LNDR-20260923-ABC'), findsOneWidget);

      // Tap the first evidence thumbnail.
      final thumbnails = find.byType(Image);
      expect(thumbnails, findsWidgets);
      await tester.ensureVisible(thumbnails.first);
      await tester.pumpAndSettle();
      await tester.tap(thumbnails.first);
      await tester.pumpAndSettle();

      // Full-screen viewer: InteractiveViewer (pinch/pan) + a close button.
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byType(PageView), findsOneWidget);
      final closeButton = find.byIcon(Icons.close_rounded);
      expect(closeButton, findsOneWidget);
      // Two photos in this set — the page indicator confirms it, not a crop.
      expect(find.text('1 / 2'), findsOneWidget);

      // Close returns to the SAME order screen with its state intact.
      await tester.tap(closeButton);
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsNothing);
      expect(find.textContaining('LNDR-20260923-ABC'), findsOneWidget);
      expect(find.textContaining('This is the vendor'), findsOneWidget, reason: 'the re-evaluation card is still showing, nothing was reset');
    });

    testWidgets('swiping moves between photos in the same evidence set', (tester) async {
      _tall(tester);
      await tester.pumpWidget(await _app(tester, _OrderRepo(_orderWithEvidence()), const OrderDetailsPage(orderId: 'o1')));
      await _settle(tester);

      await tester.ensureVisible(find.byType(Image).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Image).first);
      await tester.pumpAndSettle();
      expect(find.text('1 / 2'), findsOneWidget);

      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
    });
  });

  // ── Google Business reviews card ──────────────────────────────────────────

  group('Google Business reviews card', () {
    const addr = AddressModel(
      id: 'addr-1', userId: 'u1', line1: '1 St', city: 'Kolkata', state: 'WB', pincode: '700001', type: AddressType.home, isDefault: true,
    );

    testWidgets('shows the real rating/review count and opens the vendor\'s Google listing on tap', (tester) async {
      _tall(tester);
      final launcher = _FakeLauncher();
      UrlLauncherPlatform.instance = launcher;
      const vendor = VendorModel(
        id: 'v1', name: 'Aqua Blue Laundry', description: 'x', ownerName: 'o', phone: '9000000000', address: addr,
        googleBusinessUrl: 'https://www.google.com/maps/place/Aqua+Blue+Laundry/@1,2,17z',
        googleRating: 4.7, googleReviewCount: 326, googleBusinessName: 'Aqua Blue Laundry',
      );
      await tester.pumpWidget(await _app(tester, _VendorRepo(vendor), const VendorDetailsPage(vendorId: 'v1')));
      await _settle(tester);

      expect(find.text('Aqua Blue Laundry'), findsWidgets);
      expect(find.text('4.7'), findsOneWidget);
      expect(find.textContaining('326 Google reviews'), findsOneWidget);
      expect(find.text('View on Google'), findsOneWidget);

      await tester.tap(find.text('View on Google'));
      await tester.pumpAndSettle();
      expect(launcher.launched, ['https://www.google.com/maps/place/Aqua+Blue+Laundry/@1,2,17z']);
    });

    testWidgets('shows nothing at all for a vendor with no Google link connected', (tester) async {
      _tall(tester);
      const vendor = VendorModel(id: 'v2', name: 'Plain Laundry', description: 'x', ownerName: 'o', phone: '9000000000', address: addr);
      await tester.pumpWidget(await _app(tester, _VendorRepo(vendor), const VendorDetailsPage(vendorId: 'v2')));
      await _settle(tester);

      expect(find.text('View on Google'), findsNothing);
      expect(find.textContaining('Google reviews'), findsNothing);
    });
  });
}

class _VendorRepo extends MockCustomerRepository {
  _VendorRepo(this.vendor);
  final VendorModel vendor;

  @override
  Future<VendorModel> getVendorById(String vendorId) async => vendor;

  @override
  Future<List<ServiceModel>> getServicesByVendor(String vendorId) async => const [];
}
