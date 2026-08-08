import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../models/models.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../repositories/repositories.dart';

// ── Cart State ────────────────────────────────────────────────────────────────

class CartState {
  const CartState({
    required this.cart,
    required this.services,
    this.vendor,
    this.isInitialised = false,
  });

  final CartModel cart;
  final List<ServiceModel> services;

  /// The single vendor all cart items belong to (null if cart is empty or,
  /// in the unsupported case, spans more than one vendor).
  final VendorModel? vendor;
  final bool isInitialised;

  double get subtotal {
    double total = 0.0;
    for (final item in cart.items) {
      final svc = services.firstWhere(
        (s) => s.id == item.serviceId,
        orElse: () => const ServiceModel(
          id: '',
          vendorId: '',
          name: '',
          description: '',
          category: ServiceCategory.wash,
          minWeightKg: 0,
        ),
      );
      if (svc.id.isNotEmpty) {
        final price = svc.pricePerKg ?? svc.pricePerPiece ?? 0.0;
        total += price * item.quantity;
      }
    }
    return total;
  }

  // NOTE: These mock-phase calculations will be removed when the backend
  // delivers server-side quote amounts (spec §6 / §11).
  double get platformFee => subtotal * 0.05;
  double get gstAmount => subtotal * 0.18;
  double get total => subtotal + platformFee + gstAmount;

  int get totalQuantity => cart.itemCount;

  CartState copyWith({
    CartModel? cart,
    List<ServiceModel>? services,
    VendorModel? vendor,
    bool? isInitialised,
  }) =>
      CartState(
        cart: cart ?? this.cart,
        services: services ?? this.services,
        vendor: vendor ?? this.vendor,
        isInitialised: isInitialised ?? this.isInitialised,
      );
}

// ── Cart Notifier ─────────────────────────────────────────────────────────────

class CartNotifier extends StateNotifier<CartState> {
  CartNotifier(this._repo)
      : super(CartState(cart: CartModel(items: const []), services: const []));

  final CustomerRepository _repo;

  /// Loads cart from repository.  Safe to call multiple times;
  /// skips the fetch if already initialised unless [force] = true.
  Future<void> init({bool force = false}) async {
    if (state.isInitialised && !force) return;

    final cart = await _repo.getCart();
    final services = await _resolveServicesForCart(cart);
    final vendor = await _resolveVendorForCart(cart);
    state = CartState(
      cart: cart,
      services: services,
      vendor: vendor,
      isInitialised: true,
    );
  }

  /// Force-refreshes cart + services.  Called by VendorDetailsPage after
  /// adding items so the Cart tab is up-to-date without requiring a tab switch.
  Future<void> refresh() => init(force: true);

  /// Resolves service metadata (name, price, image) directly from the
  /// vendor(s) referenced by cart items — not by scanning every nearby
  /// vendor and matching on id, which silently breaks whenever the vendor
  /// falls outside the customer's current address radius or shares a
  /// garment-type id with another vendor.
  Future<List<ServiceModel>> _resolveServicesForCart(CartModel cart) async {
    final vendorIds = cart.items
        .map((i) => i.vendorId)
        .where((id) => id.isNotEmpty)
        .toSet();

    final services = <ServiceModel>[];
    for (final vendorId in vendorIds) {
      try {
        services.addAll(await _repo.getServicesByVendor(vendorId));
      } catch (_) {}
    }
    // Deduplicate by id.
    final seen = <String>{};
    return services.where((s) => seen.add(s.id)).toList();
  }

  Future<VendorModel?> _resolveVendorForCart(CartModel cart) async {
    final vendorIds = cart.items
        .map((i) => i.vendorId)
        .where((id) => id.isNotEmpty)
        .toSet();
    if (vendorIds.length != 1) return null;
    try {
      return await _repo.getVendorById(vendorIds.first);
    } catch (_) {
      return null;
    }
  }

  Future<void> updateQuantity(String serviceId, int newQty) async {
    final item = state.cart.items.firstWhere(
      (i) => i.serviceId == serviceId,
      orElse: () => CartItem(id: '', serviceId: '', quantity: 0),
    );
    if (item.id.isEmpty) return;

    final CartModel updated;
    if (newQty <= 0) {
      updated = await _repo.removeFromCart(item.id);
    } else {
      updated =
          await _repo.updateCartItem(cartItemId: item.id, quantity: newQty);
    }
    state = state.copyWith(cart: updated);
  }

  Future<void> clear() async {
    await _repo.clearCart();
    state = const CartState(
        cart: CartModel(items: []), services: [], isInitialised: true);
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

/// NOT autoDispose — cart state persists across tab switches.
/// Call cartStateProvider.notifier.refresh() after adding items from
/// vendor details page.
final cartStateProvider = StateNotifierProvider<CartNotifier, CartState>((ref) {
  final repo = ref.watch(customerRepositoryProvider);
  return CartNotifier(repo);
});

/// Active "milestone perks" tiers (Cart Milestones) for the widget floating
/// above the bottom nav. Empty for signed-out users; the backend already
/// filters out tiers the signed-in customer isn't eligible for.
final cartMilestoneTiersProvider =
    FutureProvider<List<CartMilestoneTier>>((ref) async {
  if (ref.watch(authProvider) is! AuthAuthenticated) {
    return const [];
  }
  final repo = ref.watch(customerRepositoryProvider);
  return repo.getActiveCartMilestoneTiers();
});
