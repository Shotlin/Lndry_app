import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../models/models.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../repositories/repositories.dart';
import '../../../../shared/repositories/base_repository.dart';

/// Provider for list of all laundry categories on Home screen
final homeCategoriesProvider = FutureProvider<List<CategoryModel>>((ref) async {
  final repo = ref.watch(customerRepositoryProvider);
  return repo.getCategories();
});

/// Provider for the promotional banner carousel on Home screen
final homeBannersProvider = FutureProvider<List<BannerModel>>((ref) async {
  final repo = ref.watch(customerRepositoryProvider);
  return repo.getBanners();
});

/// Provider for nearby/recommended vendors list on Home screen
final homeVendorsProvider = FutureProvider<List<VendorModel>>((ref) async {
  final repo = ref.watch(customerRepositoryProvider);
  double? lat;
  double? lng;

  if (ref.watch(authProvider) is AuthAuthenticated) {
    final addresses = await repo.getAddresses();
    if (addresses.isNotEmpty) {
      final addr = addresses.firstWhere(
        (a) => a.isDefault,
        orElse: () => addresses.first,
      );
      lat = addr.coordinates?.latitude;
      lng = addr.coordinates?.longitude;
    }
  }

  final response = await repo.getVendors(
    categoryId: null,
    search: null,
    params: PaginationParams(pageSize: 10, lat: lat, lng: lng),
  );
  return response.items;
});

/// Provider for recommended services on Home screen
final homeRecommendedServicesProvider =
    FutureProvider<List<ServiceModel>>((ref) async {
  final repo = ref.watch(customerRepositoryProvider);
  try {
    final vendors = await ref.watch(homeVendorsProvider.future);
    if (vendors.isNotEmpty) {
      return repo.getServicesByVendor(vendors.first.id);
    }
  } catch (_) {}
  return [];
});

/// Provider for active orders tracker on Home screen
final activeOrdersProvider = FutureProvider<List<OrderModel>>((ref) async {
  if (ref.watch(authProvider) is! AuthAuthenticated) return [];
  final repo = ref.watch(customerRepositoryProvider);
  final response = await repo.getMyOrders(
    params: const PaginationParams(pageSize: 5),
  );
  final active = response.items.where((o) => o.status.isActive).toList();

  // A walk-in order the vendor is still working on (booked, in process,
  // ready...) is active too — only finished ones go to history.
  List<OrderModel> storeActive = const [];
  try {
    storeActive =
        (await repo.getMyStoreOrders()).where((o) => o.status.isActive).toList();
  } catch (_) {
    // Bonus data — never let it take down the real active-order list.
  }

  return [...active, ...storeActive]
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
});

/// Provider for previous order history on Home screen. Merges real
/// (marketplace) orders with finished "Laundry Store" walk-in counter
/// orders; a walk-in order still in progress is in [activeOrdersProvider].
final pastOrdersProvider = FutureProvider<List<OrderModel>>((ref) async {
  if (ref.watch(authProvider) is! AuthAuthenticated) return [];
  final repo = ref.watch(customerRepositoryProvider);
  final response = await repo.getMyOrders(
    params: const PaginationParams(pageSize: 10),
  );
  final pastOrders = response.items.where((o) => !o.status.isActive).toList();

  List<OrderModel> storeOrders = const [];
  try {
    storeOrders = await repo.getMyStoreOrders();
  } catch (_) {
    // Store-order history is a bonus, not core order tracking — never let a
    // hiccup on this call take down the real order list.
  }

  final merged = [...pastOrders, ...storeOrders.where((o) => !o.status.isActive)]
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return merged;
});

/// User address display provider on Home screen
final currentAddressProvider = FutureProvider<AddressModel?>((ref) async {
  if (ref.watch(authProvider) is! AuthAuthenticated) return null;
  final repo = ref.watch(customerRepositoryProvider);
  final addresses = await repo.getAddresses();
  if (addresses.isEmpty) return null;
  return addresses.firstWhere((a) => a.isDefault,
      orElse: () => addresses.first);
});
