import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lndry/api/repositories/api_customer_repository.dart';
import 'package:lndry/core/services/storage_service.dart';
import 'package:lndry/features/cart/presentation/providers/cart_providers.dart';
import 'package:lndry/features/vendor_details/presentation/providers/vendor_details_providers.dart';
import 'package:lndry/models/models.dart';
import 'package:lndry/repositories/repositories.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Two vendors that offer the SAME garment type (the same service id), which is
/// exactly what used to make vendor B inherit vendor A's cart.
class _Repo extends ApiCustomerRepository {
  _Repo(StorageService storage) : super(dio: Dio(), storage: storage);

  static const garment = 'garment-wash-fold';

  @override
  Future<List<ServiceModel>> getServicesByVendor(String vendorId) async => [
        ServiceModel(
          id: garment,
          vendorId: vendorId,
          name: 'Wash & Fold',
          description: 'Laundry Services',
          category: ServiceCategory.wash,
          pricePerKg: vendorId == 'A' ? 80 : 88,
          minWeightKg: 1,
        ),
      ];

  @override
  Future<VendorModel> getVendorById(String vendorId) async => throw Exception('n/a');
}

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final repo = _Repo(StorageService(prefs: prefs));
  final container = ProviderContainer(overrides: [customerRepositoryProvider.overrideWithValue(repo)]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('repository: each vendor has its own cart, keyed by vendor + service', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = _Repo(StorageService(prefs: await SharedPreferences.getInstance()));

    await repo.addToCart(serviceId: _Repo.garment, vendorId: 'A', quantity: 1);
    expect(repo.activeCartVendorId, 'A');
    expect((await repo.getCart()).items.map((i) => [i.vendorId, i.quantity]), [['A', 1]]);

    // Opening vendor B: nothing of A's is visible there.
    repo.setActiveCartVendor('B');
    expect((await repo.getCart()).items, isEmpty);
    await repo.addToCart(serviceId: _Repo.garment, vendorId: 'B', quantity: 3);
    expect((await repo.getCart()).items.map((i) => [i.vendorId, i.quantity]), [['B', 3]]);

    // Back to A: its cart is exactly as it was.
    repo.setActiveCartVendor('A');
    expect((await repo.getCart()).items.map((i) => [i.vendorId, i.quantity]), [['A', 1]]);

    // Clearing/removing only touches the vendor in play.
    await repo.clearCart();
    expect((await repo.getCart()).items, isEmpty);
    repo.setActiveCartVendor('B');
    expect((await repo.getCart()).items.single.quantity, 3);
    final id = (await repo.getCart()).items.single.id;
    expect(id, contains('B'), reason: 'a line id carries its vendor');
  });

  test('vendor screens: B never inherits A\'s items even for the same service id', () async {
    final c = await _container();

    final a = c.read(vendorCartProvider('A').notifier);
    await a.init('A');
    await a.updateQuantity(_Repo.garment, 1);
    expect(c.read(vendorCartProvider('A')).items.single.quantity, 1);

    final b = c.read(vendorCartProvider('B').notifier);
    await b.init('B');
    expect(c.read(vendorCartProvider('B')).items, isEmpty, reason: 'B starts empty');
    expect(c.read(vendorCartProvider('B')).subtotal, 0);

    await b.updateQuantity(_Repo.garment, 2);
    expect(c.read(vendorCartProvider('B')).items.single.quantity, 2);
    expect(c.read(vendorCartProvider('B')).items.single.vendorId, 'B');
    // A's screen state is untouched.
    expect(c.read(vendorCartProvider('A')).items.single.quantity, 1);
    expect(c.read(vendorCartProvider('A')).items.single.vendorId, 'A');
  });

  test('checkout/cart read only the vendor in play', () async {
    final c = await _container();
    final repo = c.read(customerRepositoryProvider);

    await c.read(vendorCartProvider('A').notifier).init('A');
    await c.read(vendorCartProvider('A').notifier).updateQuantity(_Repo.garment, 2);
    await c.read(vendorCartProvider('B').notifier).init('B');
    await c.read(vendorCartProvider('B').notifier).updateQuantity(_Repo.garment, 1);

    // B is in play: checkout would contain only B's line.
    await c.read(cartStateProvider.notifier).refresh();
    var cart = c.read(cartStateProvider).cart;
    expect(cart.items.map((i) => [i.vendorId, i.quantity]), [['B', 1]]);

    // Continue from A: put A in play, and checkout contains only A's line.
    repo.setActiveCartVendor('A');
    await c.read(cartStateProvider.notifier).refresh();
    cart = c.read(cartStateProvider).cart;
    expect(cart.items.map((i) => [i.vendorId, i.quantity]), [['A', 2]]);
    expect(cart.items.every((i) => i.vendorId == 'A'), isTrue, reason: 'one vendor per checkout');
  });

  test('a pickup choice is remembered per vendor and never applied to another', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    const a = PickupSelection(vendorId: 'A', date: '2026-09-20', slotId: 's1', startTime: '08:00:00', endTime: '10:00:00');
    const b = PickupSelection(vendorId: 'B', date: '2026-09-21', slotId: 's9', startTime: '14:00:00', endTime: '16:00:00');
    c.read(pickupSelectionProvider.notifier).state = {'A': a};
    c.read(pickupSelectionProvider.notifier).state = {...c.read(pickupSelectionProvider), 'B': b};
    final all = c.read(pickupSelectionProvider);
    expect(all['A']!.slotId, 's1');
    expect(all['B']!.slotId, 's9');
    expect(all['B']!.vendorId, 'B');
    expect(all['C'], isNull);
  });
}
