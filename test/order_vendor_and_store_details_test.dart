import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lndry/api/repositories/api_customer_repository.dart';
import 'package:lndry/core/services/storage_service.dart';
import 'package:lndry/features/orders/presentation/pages/order_details_page.dart';
import 'package:lndry/features/orders/presentation/pages/orders_list_page.dart';
import 'package:lndry/models/models.dart';
import 'package:lndry/providers/auth_provider.dart';
import 'package:lndry/repositories/repositories.dart';
import 'package:lndry/shared/repositories/base_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _storeDetail = StoreOrderDetail(
  id: 'so-1',
  orderNumber: 'LND-26-00002',
  vendorName: 'Shotlin Laundry Business',
  vendorPhone: '+919999999999',
  vendorAddress: '12 MG Road, Kolkata, 700001',
  status: 'IN_PROCESS',
  items: [
    (
      name: 'Shirt',
      serviceName: 'Wash & Steam Iron',
      qty: 2.0,
      unit: 'piece',
      rate: 60.0,
      amount: 120.0,
    ),
  ],
  subtotal: 120,
  charges: 5,
  discount: 0,
  tax: 6,
  total: 131,
  amountPaid: 50,
  payments: [
    StorePaymentLine(modeLabel: 'UPI', amount: 30, at: _at),
    StorePaymentLine(modeLabel: 'Cash', amount: 20, at: _at),
  ],
  placedAt: _at,
  notes: 'Handle with care',
);
final _at = DateTime(2026, 9, 18, 10, 30);

OrderModel _order({
  required String id,
  String? vendorName,
  String source = 'MARKETPLACE',
  OrderStatus status = OrderStatus.delivered,
}) =>
    OrderModel(
      id: id,
      orderNumber: 'ORD-$id',
      customerId: 'u1',
      vendorId: source == 'STORE' ? 'v1' : '',
      vendorName: vendorName,
      items: const [],
      status: status,
      total: 100,
      source: source,
      createdAt: DateTime(2026, 9, 18),
    );

class _Repo extends MockCustomerRepository {
  _Repo({
    this.orders = const [],
    this.storeOrders = const [],
    this.store,
    this.orderById,
  });

  final List<OrderModel> orders;
  final List<OrderModel> storeOrders;
  final StoreOrderDetail? store;
  final OrderModel? orderById;

  @override
  Future<PaginatedResponse<OrderModel>> getMyOrders({
    PaginationParams params = const PaginationParams(),
  }) async =>
      PaginatedResponse(
        items: orders,
        meta: PaginationMeta(
          currentPage: 1,
          totalPages: 1,
          totalItems: orders.length,
          pageSize: 10,
        ),
      );

  @override
  Future<List<OrderModel>> getMyStoreOrders() async => storeOrders;

  @override
  Future<OrderModel> getOrderById(String orderId) async {
    if (orderById != null) return orderById!;
    // Exactly what the real backend does for a walk-in order's id.
    throw DioException(
      requestOptions: RequestOptions(path: '/orders/$orderId'),
      response: Response(
        requestOptions: RequestOptions(path: '/orders/$orderId'),
        statusCode: 404,
      ),
    );
  }

  @override
  Future<StoreOrderDetail?> findStoreOrder(String id) async => store;

  @override
  Future<VendorModel> getVendorById(String vendorId) async =>
      throw Exception('vendor lookup unavailable');
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

class _SignedInAuth extends AuthNotifier {
  _SignedInAuth(super.repo, super.storage);
  void signIn() => state = const AuthAuthenticated(UserModel(
        id: 'u1',
        name: 'Sayan',
        phone: '9999999999',
        role: UserRole.customer,
      ));
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
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('opening an order', () {
    testWidgets('a walk-in order opens (no more "Order Not Found")', (tester) async {
      _bigScreen(tester);
      await tester.pumpWidget(_app(
        const OrderDetailsPage(orderId: 'so-1'),
        [customerRepositoryProvider.overrideWithValue(_Repo(store: _storeDetail))],
      ));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Order Not Found'), findsNothing);
      expect(find.text('Order #LND-26-00002'), findsOneWidget);
      // Vendor first, with its contact details.
      expect(find.text('Shotlin Laundry Business'), findsOneWidget);
      expect(find.text('12 MG Road, Kolkata, 700001'), findsOneWidget);
      expect(find.text('+919999999999'), findsOneWidget);
      // Counter wording + label.
      expect(find.text('In Process'), findsOneWidget);
      expect(find.text('Laundry Store'), findsOneWidget);
      // Items, bill, payments, notes.
      expect(find.text('Shirt'), findsOneWidget);
      expect(find.textContaining('Wash & Steam Iron'), findsOneWidget);
      expect(find.text('Bill Summary'), findsOneWidget);
      expect(find.text('Balance due'), findsOneWidget);
      expect(find.textContaining('UPI'), findsOneWidget);
      expect(find.textContaining('Cash'), findsOneWidget);
      expect(find.text('Handle with care'), findsOneWidget);
      // None of the pickup-and-delivery machinery.
      expect(find.text('Track Order'), findsNothing);
      expect(find.text('Cancel Order'), findsNothing);
    });

    testWidgets('an id that is neither an app order nor a walk-in order still errors',
        (tester) async {
      await tester.pumpWidget(_app(
        const OrderDetailsPage(orderId: 'nope'),
        <Override>[customerRepositoryProvider.overrideWithValue(_Repo())],
      ));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Order Not Found'), findsOneWidget);
    });

    testWidgets('a normal order shows its vendor even if the vendor lookup fails',
        (tester) async {
      _bigScreen(tester);
      await tester.pumpWidget(_app(
        const OrderDetailsPage(orderId: 'o1'),
        [
          customerRepositoryProvider.overrideWithValue(_Repo(
            orderById: _order(id: 'o1', vendorName: 'Sparkle Cleaners'),
          )),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      // The existing PriceCard overflows under the wide test font (same reason
      // responsive_help_page_test drains layout exceptions) — not what's under test.
      while (tester.takeException() != null) {}
      expect(find.text('Sparkle Cleaners'), findsOneWidget);
    });
  });

  group('order list shows the vendor on every order', () {
    testWidgets('active and history tiles, and no Cancel/Reorder for walk-in orders',
        (tester) async {
      _bigScreen(tester);
      final fake = _Repo(
        orders: [
          _order(id: 'a1', vendorName: 'Sparkle Cleaners', status: OrderStatus.processing),
          _order(id: 'p1', vendorName: 'Fresh Fold Co', status: OrderStatus.delivered),
        ],
        storeOrders: [
          _order(id: 's1', vendorName: 'Shotlin Laundry Business', source: 'STORE', status: OrderStatus.delivered),
          // Booked at the counter: cancellable in the delivery app's terms, but
          // a walk-in order must never offer Cancel.
          _order(id: 's2', vendorName: 'Shotlin Laundry Business', source: 'STORE', status: OrderStatus.vendorAccepted),
        ],
      );
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

      // Active tab: real order + the in-progress walk-in order.
      expect(find.text('Sparkle Cleaners'), findsOneWidget);
      expect(find.text('Shotlin Laundry Business'), findsOneWidget);
      expect(find.text('Booked'), findsOneWidget); // counter wording, not "Scheduled"
      expect(find.text('Scheduled'), findsNothing);
      expect(find.text('Cancel'), findsNothing);

      await tester.tap(find.text('Order History'));
      await tester.pumpAndSettle();
      expect(find.text('Fresh Fold Co'), findsOneWidget);
      expect(find.text('Shotlin Laundry Business'), findsOneWidget);
      expect(find.text('Laundry Store'), findsOneWidget);
      // Reorder for the real order only.
      expect(find.text('Reorder'), findsOneWidget);
    });
  });

  group('app understands the real backend responses', () {
    Future<ApiCustomerRepository> repoFor(Map<String, dynamic> Function(RequestOptions) reply) async {
      final dio = Dio(BaseOptions(baseUrl: 'http://x'));
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        final body = reply(o);
        if (body['__status'] != null) {
          h.reject(DioException(
            requestOptions: o,
            response: Response(requestOptions: o, statusCode: body['__status'] as int),
            type: DioExceptionType.badResponse,
          ));
        } else {
          h.resolve(Response(requestOptions: o, data: body, statusCode: 200));
        }
      }));
      SharedPreferences.setMockInitialValues({});
      return ApiCustomerRepository(
        dio: dio,
        storage: _TestStorage(prefs: await SharedPreferences.getInstance()),
      );
    }

    test('order: camelCase shopId + vendorName from GET /orders/:id', () async {
      final repo = await repoFor((_) => {
            'success': true,
            'data': {
              'id': 'o1',
              'orderNumber': 'LNDR-1',
              'shopId': 'vendor-9',
              'vendorName': 'Sparkle Cleaners',
              'status': 'PROCESSING',
              'items': <Object?>[],
            },
          });
      final o = await repo.getOrderById('o1');
      expect(o.vendorId, 'vendor-9');
      expect(o.vendorName, 'Sparkle Cleaners');
    });

    test('walk-in list: real status, vendor, paid amount, expected date', () async {
      final repo = await repoFor((_) => {
            'success': true,
            'data': [
              {
                'id': 's1', 'vendorId': 'v1', 'vendorName': 'Shotlin Laundry Business',
                'customerUserId': 'u1', 'orderNumber': 'LND-1', 'status': 'IN_PROCESS',
                'items': [{'name': 'Shirt', 'qty': 2, 'unit': 'piece', 'ratePaise': 6000, 'amountPaise': 12000}],
                'subtotalPaise': 12000, 'taxPaise': 600, 'totalPaise': 13100, 'amountPaidPaise': 5000,
                'expectedDeliveryDate': '2026-09-25T00:00:00.000Z', 'placedAt': '2026-09-18T10:00:00.000Z',
              },
              {'id': 's2', 'vendorName': 'X', 'totalPaise': 100, 'placedAt': '2026-09-01T10:00:00.000Z'},
            ],
          });
      final list = await repo.getMyStoreOrders();
      final live = list.first;
      expect(live.status, OrderStatus.processing);
      expect(live.statusLabel, 'Processing');
      expect(live.vendorName, 'Shotlin Laundry Business');
      expect(live.isPaid, isFalse);
      expect(live.amountPaid, 50.0);
      expect(live.estimatedDeliveryAt, isNotNull);
      // A legacy row (no status field) is a finished, fully paid sale.
      expect(list.last.status, OrderStatus.delivered);
      expect(list.last.isPaid, isTrue);
      expect(list.last.status.isActive, isFalse);
    });

    test('findStoreOrder: parses detail, and returns null on 404', () async {
      var missing = false;
      final repo = await repoFor((_) => missing
          ? {'__status': 404}
          : {
              'success': true,
              'data': {
                'id': 's1', 'orderNumber': 'LND-1', 'vendorName': 'Shotlin Laundry Business',
                'vendorPhone': '+91999', 'vendorAddress': '12 MG Road', 'status': 'READY',
                'items': [{'name': 'Shirt', 'serviceName': 'Wash', 'qty': 2, 'unit': 'piece', 'ratePaise': 6000, 'amountPaise': 12000}],
                'subtotalPaise': 12000, 'chargesPaise': 500, 'discountPaise': 0, 'taxPaise': 600,
                'totalPaise': 13100, 'amountPaidPaise': 5000, 'placedAt': '2026-09-18T10:00:00.000Z',
                'payments': [{'mode': 'WALLET', 'amountPaise': 5000, 'createdAt': '2026-09-18T10:05:00.000Z'}],
              },
            });
      final d = (await repo.findStoreOrder('s1'))!;
      expect(d.vendorName, 'Shotlin Laundry Business');
      expect(d.statusLabel, 'Ready');
      expect(d.items.single.amount, 120.0);
      expect(d.charges, 5.0);
      expect(d.balanceDue, closeTo(81.0, 0.001));
      expect(d.payments.single.modeLabel, 'LNDRY Wallet');

      missing = true;
      expect(await repo.findStoreOrder('nope'), isNull);
    });
  });
}
