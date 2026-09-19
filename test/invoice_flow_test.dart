import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lndry/api/repositories/api_customer_repository.dart';
import 'package:lndry/core/network/network.dart';
import 'package:lndry/core/services/storage_service.dart';
import 'package:lndry/features/orders/presentation/pages/order_details_page.dart';
import 'package:lndry/features/orders/presentation/pages/orders_list_page.dart';
import 'package:lndry/models/models.dart';
import 'package:lndry/providers/auth_provider.dart';
import 'package:lndry/repositories/repositories.dart';
import 'package:lndry/shared/repositories/base_repository.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Records what the app asks the OS to open — the invoice links.
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

OrderModel _order(String id, OrderStatus status, {String source = 'MARKETPLACE'}) => OrderModel(
      id: id,
      orderNumber: 'ORD-$id',
      customerId: 'u1',
      vendorId: '',
      vendorName: 'Sparkle Cleaners',
      items: const [],
      status: status,
      total: 100,
      source: source,
      createdAt: DateTime(2026, 9, 18),
    );

class _Repo extends MockCustomerRepository {
  _Repo({this.order, this.store, this.refusal, this.orders = const []});

  final OrderModel? order;
  final StoreOrderDetail? store;
  final ApiException? refusal;
  final List<OrderModel> orders;
  final invoiceRequests = <String>[];

  @override
  Future<OrderModel> getOrderById(String orderId) async {
    if (order != null) return order!;
    throw DioException(
      requestOptions: RequestOptions(path: '/orders/$orderId'),
      response: Response(requestOptions: RequestOptions(path: '/orders/$orderId'), statusCode: 404),
    );
  }

  @override
  Future<StoreOrderDetail?> findStoreOrder(String id) async => store;

  @override
  Future<VendorModel> getVendorById(String vendorId) async => throw Exception('n/a');

  @override
  Future<PaginatedResponse<OrderModel>> getMyOrders({
    PaginationParams params = const PaginationParams(),
  }) async =>
      PaginatedResponse(
        items: orders,
        meta: PaginationMeta(currentPage: 1, totalPages: 1, totalItems: orders.length, pageSize: 10),
      );

  @override
  Future<List<OrderModel>> getMyStoreOrders() async => const [];

  @override
  Future<InvoiceInfo> getOrderInvoice(String orderId) async {
    invoiceRequests.add(orderId);
    if (refusal != null) throw refusal!;
    return InvoiceInfo(
      id: 'inv-1',
      invoiceNumber: 'INV-2627-000001',
      orderId: orderId,
      viewUrl: 'https://api.lndry.in/api/v1/invoices/download?t=VIEW-TOKEN',
      downloadUrl: 'https://api.lndry.in/api/v1/invoices/download?t=DOWNLOAD-TOKEN',
      total: 434,
    );
  }
}

StoreOrderDetail _store(String status) => StoreOrderDetail(
      id: 'so-1',
      orderNumber: 'LND-26-00002',
      vendorName: 'Shotlin Laundry Business',
      status: status,
      items: const [],
      subtotal: 100,
      charges: 0,
      discount: 0,
      tax: 0,
      total: 100,
      amountPaid: 100,
      payments: const [],
      placedAt: DateTime(2026, 9, 18),
    );

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

class _SignedInAuth extends AuthNotifier {
  _SignedInAuth(super.repo, super.storage);
  void signIn() => state = const AuthAuthenticated(
      UserModel(id: 'u1', name: 'Sayan', phone: '9999999999', role: UserRole.customer));
}

Widget _app(Widget home, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        builder: (_, __) => MaterialApp(home: home),
      ),
    );

void _bigScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
  // The existing price card overflows under the wide test font (see
  // responsive_help_page_test) — unrelated to what is under test here.
  while (tester.takeException() != null) {}
}

void main() {
  late _FakeLauncher launcher;
  setUp(() {
    launcher = _FakeLauncher();
    UrlLauncherPlatform.instance = launcher;
  });

  group('order details', () {
    testWidgets('delivered order: View / Download open exactly the backend links', (tester) async {
      _bigScreen(tester);
      final repo = _Repo(order: _order('o1', OrderStatus.delivered));
      await tester.pumpWidget(_app(const OrderDetailsPage(orderId: 'o1'),
          [customerRepositoryProvider.overrideWithValue(repo)]));
      await _settle(tester);

      expect(find.text('Invoice'), findsOneWidget);
      expect(find.text('View Invoice'), findsOneWidget);
      expect(find.text('Download Invoice'), findsOneWidget);
      expect(repo.invoiceRequests, isEmpty, reason: 'nothing is fetched or generated until the customer asks');

      await tester.ensureVisible(find.text('View Invoice'));
      await tester.tap(find.text('View Invoice'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(repo.invoiceRequests, ['o1']);
      expect(launcher.launched, ['https://api.lndry.in/api/v1/invoices/download?t=VIEW-TOKEN']);

      await tester.tap(find.text('Download Invoice'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(repo.invoiceRequests, ['o1', 'o1'], reason: 'fresh links every time — they are short-lived');
      expect(launcher.launched.last, 'https://api.lndry.in/api/v1/invoices/download?t=DOWNLOAD-TOKEN');
    });

    testWidgets('an order that is not delivered shows no invoice', (tester) async {
      _bigScreen(tester);
      await tester.pumpWidget(_app(const OrderDetailsPage(orderId: 'o2'),
          [customerRepositoryProvider.overrideWithValue(_Repo(order: _order('o2', OrderStatus.processing)))]));
      await _settle(tester);
      expect(find.text('View Invoice'), findsNothing);
      expect(find.text('Download Invoice'), findsNothing);
    });

    testWidgets('a server refusal is shown and nothing is opened', (tester) async {
      _bigScreen(tester);
      final repo = _Repo(
        order: _order('o1', OrderStatus.delivered),
        refusal: const ApiException(
          message: 'The invoice is available once your order has been delivered.',
          statusCode: 409,
          code: 'INVOICE_NOT_AVAILABLE',
        ),
      );
      await tester.pumpWidget(_app(const OrderDetailsPage(orderId: 'o1'),
          [customerRepositoryProvider.overrideWithValue(repo)]));
      await _settle(tester);
      await tester.ensureVisible(find.text('View Invoice'));
      await tester.tap(find.text('View Invoice'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('The invoice is available once your order has been delivered.'), findsOneWidget);
      expect(launcher.launched, isEmpty);
    });

    testWidgets('walk-in order that is delivered offers the invoice', (tester) async {
      _bigScreen(tester);
      await tester.pumpWidget(_app(const OrderDetailsPage(orderId: 'so-1'),
          [customerRepositoryProvider.overrideWithValue(_Repo(store: _store('DELIVERED')))]));
      await _settle(tester);
      expect(find.text('View Invoice'), findsOneWidget);
      expect(find.text('Download Invoice'), findsOneWidget);
    });

    testWidgets('walk-in order still in process has no invoice yet', (tester) async {
      _bigScreen(tester);
      await tester.pumpWidget(_app(const OrderDetailsPage(orderId: 'so-1'),
          [customerRepositoryProvider.overrideWithValue(_Repo(store: _store('IN_PROCESS')))]));
      await _settle(tester);
      expect(find.text('Order #LND-26-00002'), findsOneWidget);
      expect(find.text('View Invoice'), findsNothing);
    });
  });

  group('order history', () {
    testWidgets('delivered orders offer invoice links; cancelled ones do not', (tester) async {
      _bigScreen(tester);
      final fake = _Repo(orders: [
        _order('d1', OrderStatus.delivered),
        _order('c1', OrderStatus.customerCancelled),
      ]);
      SharedPreferences.setMockInitialValues({'fresh_install_reset_done_v3': true});
      final storage = _TestStorage(prefs: await SharedPreferences.getInstance());
      final auth = _SignedInAuth(fake, storage);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      auth.signIn();

      await tester.pumpWidget(_app(const OrdersListPage(), [
        customerRepositoryProvider.overrideWithValue(fake),
        storageServiceProvider.overrideWithValue(storage),
        authProvider.overrideWith((ref) => auth),
      ]));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Order History'));
      await tester.pumpAndSettle();

      expect(find.text('View Invoice'), findsOneWidget); // only the delivered one
      expect(find.text('Download Invoice'), findsOneWidget);

      await tester.tap(find.text('Download Invoice'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(fake.invoiceRequests, ['d1']);
      expect(launcher.launched.single, endsWith('DOWNLOAD-TOKEN'));
    });
  });

  group('the app only consumes the backend invoice', () {
    test('InvoiceInfo mirrors the API response (no client-side maths)', () {
      final i = InvoiceInfo.fromJson({
        'id': 'a', 'invoiceNumber': 'INV-2627-000007', 'orderId': 'o', 'totalPaise': 43400,
        'paymentStatus': 'PAID', 'invoiceDate': '2026-09-19T08:00:00.000Z',
        'viewUrl': 'https://x/v', 'downloadUrl': 'https://x/d',
      });
      expect(i.invoiceNumber, 'INV-2627-000007');
      expect(i.total, 434.0);
      expect(i.viewUrl, 'https://x/v');
      expect(i.downloadUrl, 'https://x/d');
    });

    test('getOrderInvoice calls the backend invoice API and surfaces its message on refusal', () async {
      final calls = <String>[];
      final dio = Dio(BaseOptions(baseUrl: 'http://x'));
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        calls.add('${o.method} ${o.path}');
        if (o.path.endsWith('/not-delivered')) {
          h.reject(DioException(
            requestOptions: o,
            type: DioExceptionType.badResponse,
            response: Response(requestOptions: o, statusCode: 409),
            error: const ApiException(message: 'The invoice is available once your order has been delivered.', statusCode: 409),
          ));
          return;
        }
        h.resolve(Response(requestOptions: o, statusCode: 200, data: {
          'success': true,
          'data': {'id': 'a', 'invoiceNumber': 'INV-2627-000001', 'orderId': 'o1', 'viewUrl': 'https://x/v', 'downloadUrl': 'https://x/d', 'totalPaise': 100},
        }));
      }));
      SharedPreferences.setMockInitialValues({});
      final repo = ApiCustomerRepository(dio: dio, storage: _TestStorage(prefs: await SharedPreferences.getInstance()));

      final info = await repo.getOrderInvoice('o1');
      expect(calls.single, 'GET /invoices/orders/o1');
      expect(info.invoiceNumber, 'INV-2627-000001');
      await expectLater(
        repo.getOrderInvoice('not-delivered'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('delivered'))),
      );
    });

    test('no PDF / invoice-layout code or packages anywhere in the app', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      for (final pkg in ['pdf:', 'printing:', 'syncfusion_flutter_pdf', 'flutter_html', 'webview_flutter']) {
        expect(pubspec.contains(RegExp('^\\s*$pkg', multiLine: true)), isFalse, reason: 'pubspec depends on $pkg');
      }
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        final src = f.readAsStringSync();
        if (RegExp(r"package:(pdf|printing)/|pw\.Document|<html|GST Invoice|Tax Invoice", caseSensitive: false).hasMatch(src)) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty, reason: 'invoice layout must live on the backend: $offenders');
    });
  });
}
