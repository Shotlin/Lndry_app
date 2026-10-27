import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lndry/core/services/storage_service.dart';
import 'package:lndry/features/checkout/presentation/pages/checkout_page.dart';
import 'package:lndry/features/checkout/presentation/pages/payment_page.dart';
import 'package:lndry/features/orders/presentation/pages/order_details_page.dart';
import 'package:lndry/features/vendor_details/presentation/pages/vendor_details_page.dart';
import 'package:lndry/models/models.dart';
import 'package:lndry/providers/auth_provider.dart';
import 'package:lndry/repositories/repositories.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Book With Expert Check" (assisted booking), customer side. The backend owns
/// availability and wording; these tests pin how the app reacts to it.

const _user = UserModel(
  id: 'u1',
  phone: '9999999999',
  name: 'Test',
  role: UserRole.customer,
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

/// Real notifier (so `authProvider` keeps its type) but pinned to signed-in.
class _SignedIn extends AuthNotifier {
  _SignedIn(super.repo, super.storage);
  void signIn() => state = const AuthAuthenticated(_user);
}

class _Repo extends MockCustomerRepository {
  _Repo({
    this.config = const AssistedBookingConfig(
      available: true,
      title: 'Not sure what service you need?',
      subtitle: 'Book now — we will inspect your garments.',
      buttonText: 'Let the Laundry Decide',
      checkoutNote: 'Service & final price will be confirmed after garment inspection.',
      assessmentTitle: 'Laundry Assessment Required',
      assessmentMessage: 'Vendor will inspect your garments and confirm services.',
      priceLabel: 'Price after inspection',
    ),
    this.order,
  });

  AssistedBookingConfig config;
  OrderModel? order;
  final quoteCalls = <bool>[];
  int configCalls = 0;

  @override
  Future<AssistedBookingConfig> getAssistedBookingConfig(String vendorId) async {
    configCalls++;
    return config;
  }

  @override
  Future<QuoteResult> createQuote({
    required String vendorId,
    String? vendorServiceId,
    required List<QuoteGarmentLine> garmentLines,
    double? estimatedWeightKg,
    bool assisted = false,
    String? addressId,
  }) {
    quoteCalls.add(assisted);
    return super.createQuote(
      vendorId: vendorId,
      vendorServiceId: vendorServiceId,
      garmentLines: garmentLines,
      estimatedWeightKg: estimatedWeightKg,
      assisted: assisted,
      addressId: addressId,
    );
  }

  @override
  Future<OrderDraftResult> prepareOrder({
    required String quoteId,
    required String addressId,
    String? slotId,
    bool isExpressPickup = false,
    String? couponCode,
  }) async =>
      const OrderDraftResult(
        orderDraftId: 'draft-1',
        // Fees only — an assisted booking has no service price yet.
        payableAmountPaise: 3400,
        snapshot: {
          'advance_amount_paise': 5000,
          'fee_breakdown': {
            'subtotal_paise': 0,
            'delivery_fee_paise': 2900,
            'total_payable_paise': 3400,
          },
        },
      );

  @override
  Future<PaymentOrderResult> createPaymentOrder({String? orderId, String? orderDraftId}) async =>
      const PaymentOrderResult(
        paymentId: 'pay-1',
        razorpayOrderId: 'rzp-1',
        // The advance — what is actually charged for an assisted booking.
        amount: 50,
        currency: 'INR',
        keyId: 'k',
      );

  @override
  Future<OrderModel> getOrderById(String orderId) async => order!;

  @override
  Future<StoreOrderDetail?> findStoreOrder(String id) async => null;

  // Everything the screens read is built here, not loaded from the mock's JSON
  // assets: asset loading runs on the real event loop, which fake-time pumping
  // does not wait for — that made these tests flaky.
  static const _address = AddressModel(
    id: 'addr-1',
    userId: 'u1',
    line1: '12 Test Street',
    city: 'Kolkata',
    state: 'WB',
    pincode: '700001',
    type: AddressType.home,
    isDefault: true,
  );

  static const _vendor = VendorModel(
    id: 'vndr_001',
    name: 'Shotlin Laundry',
    description: 'A laundry',
    ownerName: 'Owner',
    phone: '9000000000',
    address: _address,
    expressPickupAvailable: true,
  );

  @override
  Future<VendorModel> getVendorById(String vendorId) async => _vendor;

  @override
  Future<List<ServiceModel>> getServicesByVendor(String vendorId) async => const [];

  @override
  Future<List<AddressModel>> getAddresses() async => const [_address];
}

OrderModel _order({required String bookingType, List<OrderItem> items = const [], OrderStatus status = OrderStatus.receivedAtVendor}) =>
    OrderModel(
      id: 'o1',
      orderNumber: 'LNDR-20260921-ABC',
      customerId: 'u1',
      vendorId: 'vndr_001',
      vendorName: 'Shotlin Laundry',
      items: items,
      status: status,
      total: 34,
      bookingType: bookingType,
      createdAt: DateTime(2026, 9, 21),
    );

Future<Widget> _app(WidgetTester tester, _Repo repo, Widget home, {Object? extra}) async {
  SharedPreferences.setMockInitialValues({'fresh_install_reset_done_v3': true});
  final storage = _TestStorage(prefs: await SharedPreferences.getInstance());
  final auth = _SignedIn(repo, storage);
  // Let the notifier's own session restore settle, then pin signed-in.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  auth.signIn();

  final router = GoRouter(
    initialLocation: '/',
    initialExtra: extra,
    routes: [
      GoRoute(path: '/', builder: (_, __) => home),
      GoRoute(path: '/checkout', builder: (_, s) => Scaffold(body: Text('CHECKOUT ${s.uri.queryParameters['assistedVendor']}'))),
    ],
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

/// The mock repository simulates network latency (200–600 ms per call), so
/// give the screen real time to load instead of a fixed pair of pumps.
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

void main() {
  group('config', () {
    test('uses the wording the backend sends and the availability it reports', () {
      final c = AssistedBookingConfig.fromJson({
        'available': true,
        'title': 'Need help choosing?',
        'subtitle': 'We inspect, you approve.',
        'buttonText': 'Let the Laundry Decide',
        'iconUrl': 'https://cdn/x.png',
        'checkoutNote': 'Price comes later.',
        'assessmentTitle': 'Assessment',
        'assessmentMessage': 'Msg',
        'priceLabel': 'To be evaluated',
      });
      expect(c.available, isTrue);
      expect(c.buttonText, 'Let the Laundry Decide');
      expect(c.priceLabel, 'To be evaluated');
      expect(c.iconUrl, 'https://cdn/x.png');
    });

    test('is unavailable by default and falls back to built-in wording for blanks', () {
      final c = AssistedBookingConfig.fromJson({'buttonText': '   ', 'iconUrl': ''});
      expect(c.available, isFalse);
      expect(c.buttonText, 'Book With Expert Check');
      expect(c.priceLabel, 'Price after inspection');
      expect(c.iconUrl, isNull);
      expect(AssistedBookingConfig.fallback.available, isFalse);
    });
  });

  group('order model', () {
    test('an assisted order with nothing priced yet is awaiting assessment', () {
      expect(_order(bookingType: 'ASSISTED').awaitingAssessment, isTrue);
    });

    test('once the laundry has chosen services, or for a normal order, it is not', () {
      const item = OrderItem(serviceId: 's', serviceName: 'Shirt', quantity: 2, unitPrice: 50, totalPrice: 100);
      expect(_order(bookingType: 'ASSISTED', items: const [item]).awaitingAssessment, isFalse);
      expect(_order(bookingType: 'ASSISTED', items: const [item]).isAssisted, isTrue);
      expect(_order(bookingType: 'STANDARD').awaitingAssessment, isFalse);
      expect(_order(bookingType: 'STANDARD').isAssisted, isFalse);
    });
  });

  group('vendor page', () {
    testWidgets('shows the admin-worded option, and it starts assisted checkout for that vendor', (tester) async {
      _tall(tester);
      final repo = _Repo();
      await tester.pumpWidget(await _app(tester, repo, const VendorDetailsPage(vendorId: 'vndr_001')));
      await _settle(tester);

      expect(find.text('Not sure what service you need?'), findsOneWidget);
      expect(find.text('Let the Laundry Decide'), findsOneWidget, reason: 'button text comes from the backend');

      await tester.ensureVisible(find.text('Let the Laundry Decide'));
      await tester.tap(find.text('Let the Laundry Decide'));
      await _settle(tester);

      expect(find.text('CHECKOUT vndr_001'), findsOneWidget);
    });

    testWidgets('is not shown for a vendor that does not offer it', (tester) async {
      _tall(tester);
      final repo = _Repo(config: AssistedBookingConfig.fallback);
      await tester.pumpWidget(await _app(tester, repo, const VendorDetailsPage(vendorId: 'vndr_001')));
      await _settle(tester);

      expect(repo.configCalls, greaterThan(0));
      // The page itself has loaded (this is not a blank screen)...
      expect(find.text('Services'), findsWidgets);
      // ...it just doesn't offer the option.
      expect(find.byKey(const ValueKey('assisted_booking_card')), findsNothing);
      expect(find.text('Book With Expert Check'), findsNothing);
    });
  });

  group('order details', () {
    testWidgets('shows the assessment card and "price after inspection", not a fee-only total', (tester) async {
      _tall(tester);
      final repo = _Repo(order: _order(bookingType: 'ASSISTED'));
      await tester.pumpWidget(await _app(tester, repo, const OrderDetailsPage(orderId: 'o1')));
      await _settle(tester);

      expect(find.text('Laundry Assessment Required'), findsOneWidget);
      expect(find.text('Price after inspection'), findsOneWidget);
      expect(find.text('Order Summary'), findsNothing);
    });

    testWidgets('a normal order shows none of it', (tester) async {
      _tall(tester);
      final repo = _Repo(order: _order(bookingType: 'STANDARD'));
      await tester.pumpWidget(await _app(tester, repo, const OrderDetailsPage(orderId: 'o1')));
      await _settle(tester);

      expect(find.text('Laundry Assessment Required'), findsNothing);
    });

    testWidgets('once the laundry has reviewed it, the review banner replaces the assessment card', (tester) async {
      _tall(tester);
      final repo = _Repo(order: _order(bookingType: 'ASSISTED', status: OrderStatus.reconciliationPending));
      await tester.pumpWidget(await _app(tester, repo, const OrderDetailsPage(orderId: 'o1')));
      await _settle(tester);

      expect(find.text('Laundry Assessment Required'), findsNothing);
      expect(find.text('Services & price ready for your approval'), findsOneWidget);
      expect(find.text('Your order total was updated'), findsNothing);
    });
  });

  group('checkout', () {
    testWidgets('books with no cart: explains the inspection, shows no fake price, quotes as assisted', (tester) async {
      _tall(tester);
      final repo = _Repo();
      await tester.pumpWidget(await _app(tester, repo, const CheckoutPage(assistedVendorId: 'vndr_001')));
      await _settle(tester, ms: 6000);

      // Not the "nothing to checkout" empty state a cart-less checkout used to show.
      expect(find.text('Nothing to checkout'), findsNothing);
      expect(find.byKey(const ValueKey('checkout_assisted_order_card')), findsOneWidget);
      expect(find.text('Laundry Assessment Required'), findsOneWidget);
      expect(find.text('Price after inspection'), findsWidgets);
      expect(find.text('Service & final price will be confirmed after garment inspection.'), findsWidgets);

      // What is charged now is the advance, not the fee-only draft total.
      expect(find.text('Pay now to confirm pickup'), findsOneWidget);
      expect(find.text('₹50.00'), findsWidgets);
      expect(find.text('₹34.00'), findsNothing);

      // No coupon section: coupons need a service price.
      expect(find.byKey(const ValueKey('checkout_coupon_section')), findsNothing);

      // The quote really was requested as an assisted booking (no garments).
      expect(repo.quoteCalls, isNotEmpty);
      expect(repo.quoteCalls.every((assisted) => assisted), isTrue);
    });
  });

  group('payment', () {
    testWidgets('shows the advance and "price after inspection" — no cart needed, no fake estimate', (tester) async {
      _tall(tester);
      final repo = _Repo();
      await tester.pumpWidget(await _app(
        tester,
        repo,
        const PaymentPage(),
        extra: const CheckoutSession(
          deliveryAddressId: 'addr-1',
          pickupAddressId: 'addr-1',
          finalPrice: 34,
          orderDraftId: 'draft-1',
          isAssisted: true,
          assistedVendorId: 'vndr_001',
          advanceAmountPaise: 5000,
        ),
      ));
      await _settle(tester);

      // Not the "Nothing to pay for / your cart is empty" state.
      expect(find.text('Nothing to pay for'), findsNothing);
      expect(find.text('Service price'), findsOneWidget);
      expect(find.text('Price after inspection'), findsOneWidget);
      expect(find.text('Pay now to book slot'), findsOneWidget);
      expect(find.text('Total order estimate'), findsNothing);
      expect(find.text('Pay ₹50.00 Now'), findsOneWidget);
      // The fee-only draft total must not be presented as an order total.
      expect(find.text('₹34.00'), findsNothing);
    });
  });
}
