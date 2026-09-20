import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../models/models.dart';
import '../../../../repositories/repositories.dart';
import '../../../cart/presentation/providers/cart_providers.dart';

class VendorCartState {
  const VendorCartState({
    required this.items,
    required this.services,
  });

  final List<CartItem> items;
  final List<ServiceModel> services;

  double get subtotal {
    double total = 0.0;
    for (final item in items) {
      final svc = services.firstWhere((s) => s.id == item.serviceId,
          orElse: () => const ServiceModel(
              id: '',
              vendorId: '',
              name: '',
              description: '',
              category: ServiceCategory.wash,
              minWeightKg: 0));
      if (svc.id.isNotEmpty) {
        final price = svc.pricePerKg ?? svc.pricePerPiece ?? 0.0;
        total += price * item.quantity;
      }
    }
    return total;
  }

  double get platformFee => subtotal * 0.05; // 5% platform fee
  double get gstAmount => subtotal * 0.18; // 18% GST
  double get total => subtotal + platformFee + gstAmount;

  int get totalQuantity => items.fold(0, (sum, item) => sum + item.quantity);
}

class VendorCartNotifier extends StateNotifier<VendorCartState> {
  VendorCartNotifier(this._repo, this._ref, this._vendorId)
      : super(const VendorCartState(items: [], services: []));

  final CustomerRepository _repo;
  final Ref _ref;

  /// The vendor this cart belongs to — fixed for the life of the notifier.
  final String _vendorId;

  Future<void> init(String vendorId, {bool includeCart = true}) async {
    // This vendor's cart is the one in play from here on (Checkout and the
    // Cart screen read the vendor in play).
    _repo.setActiveCartVendor(vendorId);
    final list = await _repo.getServicesByVendor(vendorId);
    final filteredItems = <CartItem>[];

    if (includeCart) {
      final cart = await _repo.getCart();
      // Only THIS vendor's lines. Matching on the service id alone would pull
      // in another vendor's cart, because many vendors offer the same garment
      // type (same id).
      final svcIds = list.map((s) => s.id).toSet();
      filteredItems.addAll(
        cart.items.where(
          (i) => i.vendorId == vendorId && svcIds.contains(i.serviceId),
        ),
      );
    }

    state = VendorCartState(
      items: filteredItems,
      services: list,
    );
  }

  Future<void> updateQuantity(String serviceId, int delta) async {
    // Returning to an earlier vendor screen: act on THIS vendor's cart.
    _repo.setActiveCartVendor(_vendorId);
    final updatedItems = List<CartItem>.from(state.items);
    final idx = updatedItems.indexWhere((i) => i.serviceId == serviceId);

    if (idx >= 0) {
      final current = updatedItems[idx];
      final newQty = current.quantity + delta;

      if (newQty <= 0) {
        updatedItems.removeAt(idx);
        final c = await _repo.getCart();
        final item = c.items.firstWhere((i) => i.serviceId == serviceId,
            orElse: () => const CartItem(id: '', serviceId: '', quantity: 0));
        if (item.id.isNotEmpty) await _repo.removeFromCart(item.id);
      } else {
        updatedItems[idx] = current.copyWith(quantity: newQty);
        final c = await _repo.getCart();
        final item = c.items.firstWhere((i) => i.serviceId == serviceId,
            orElse: () => const CartItem(id: '', serviceId: '', quantity: 0));
        if (item.id.isNotEmpty) {
          await _repo.updateCartItem(cartItemId: item.id, quantity: newQty);
        }
      }
    } else if (delta > 0) {
      final newItem = CartItem(
        id: 'ci_${DateTime.now().millisecondsSinceEpoch}',
        serviceId: serviceId,
        vendorId: _vendorId,
        quantity: delta,
      );
      updatedItems.add(newItem);
      await _repo.addToCart(
          serviceId: serviceId, vendorId: _vendorId, quantity: delta);
    }

    state = VendorCartState(
      items: updatedItems,
      services: state.services,
    );

    await _ref.read(cartStateProvider.notifier).refresh();
  }
}

/// One cart notifier per vendor — vendor A's screen and vendor B's screen never
/// share a selected-service list.
final vendorCartProvider = StateNotifierProvider.autoDispose
    .family<VendorCartNotifier, VendorCartState, String>((ref, vendorId) {
  final repo = ref.watch(customerRepositoryProvider);
  return VendorCartNotifier(repo, ref, vendorId);
});
