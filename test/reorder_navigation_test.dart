import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lndry/features/orders/presentation/pages/order_details_page.dart';
import 'package:lndry/models/models.dart';
import 'package:lndry/repositories/repositories.dart';

class _Repo extends MockCustomerRepository {
  _Repo(this.result);
  final ReorderResult result;
  int reorders = 0;

  @override
  Future<OrderModel> getOrderById(String orderId) async => OrderModel(
        id: orderId,
        orderNumber: 'ORD-1',
        customerId: 'u1',
        vendorId: 'v1',
        vendorName: 'Shotlin Laundry Business',
        items: const [],
        status: OrderStatus.vendorRejected,
        total: 100,
        createdAt: DateTime(2026, 9, 19),
      );

  @override
  Future<StoreOrderDetail?> findStoreOrder(String id) async => null;

  @override
  Future<VendorModel> getVendorById(String vendorId) async => throw Exception('n/a');

  @override
  Future<ReorderResult> reorder(String orderId) async {
    reorders++;
    return result;
  }
}

Widget _app(_Repo repo) {
  final router = GoRouter(
    initialLocation: '/orders/o1',
    routes: [
      GoRoute(path: '/orders/:id', builder: (_, s) => OrderDetailsPage(orderId: s.pathParameters['id']!)),
      GoRoute(path: '/checkout', builder: (_, __) => const Scaffold(body: Text('CHECKOUT SCREEN'))),
      GoRoute(path: '/cart', builder: (_, __) => const Scaffold(body: Text('LEGACY CART SCREEN'))),
    ],
  );
  return ProviderScope(
    overrides: [customerRepositoryProvider.overrideWithValue(repo)],
    child: ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      builder: (_, __) => MaterialApp.router(routerConfig: router),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
  while (tester.takeException() != null) {}
}

void main() {
  for (final entry in {
    'everything is still available': const ReorderResult(success: true, message: '3 items added to your cart.', itemCount: 3),
    'one item is no longer offered': const ReorderResult(
      success: true,
      message: '2 items added to your cart. Not available right now: Saree.',
      itemCount: 2,
      warnings: ['Saree'],
    ),
  }.entries) {
    testWidgets('Reorder goes straight to Checkout, never the legacy Cart — ${entry.key}', (tester) async {
      tester.view.physicalSize = const Size(390, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _Repo(entry.value);
      await tester.pumpWidget(_app(repo));
      await _settle(tester);

      await tester.ensureVisible(find.text('Reorder'));
      await tester.tap(find.text('Reorder'));
      await _settle(tester);
      await tester.pumpAndSettle();
      while (tester.takeException() != null) {}

      expect(repo.reorders, 1);
      expect(find.text('CHECKOUT SCREEN'), findsOneWidget);
      expect(find.text('LEGACY CART SCREEN'), findsNothing);
      if (entry.value.warnings.isNotEmpty) {
        expect(find.textContaining('Not available right now: Saree'), findsOneWidget, reason: 'only the missing item is flagged');
      }
    });
  }
}
