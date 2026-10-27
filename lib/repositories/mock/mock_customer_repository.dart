import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../api/repositories/api_customer_repository.dart';
import '../../config/env.dart';
import '../../core/network/network.dart';
import '../../core/services/storage_service.dart';
import '../../models/models.dart';
import '../../shared/repositories/base_repository.dart';
import '../abstract/customer_repository.dart';

/// Mock implementation of [CustomerRepository].
/// Reads data from assets/mock/*.json files.
/// Replace this with [ApiCustomerRepository] when backend is available —
/// the UI layer never needs to change because it only depends on the abstract interface.
class MockCustomerRepository implements CustomerRepository {
  MockCustomerRepository();

  // ── Auth (mock implementation for offline dev) ─────────────────────────────

  @override
  Future<SendOtpResult> sendOtp(String phone) async {
    await _delay();
    return SendOtpResult(
      challengeId: 'mock_challenge_${DateTime.now().millisecondsSinceEpoch}',
      expiresIn: 300,
      devOtp: '1234',
    );
  }

  @override
  Future<VerifyOtpResult> verifyOtp({
    required String phone,
    required String otp,
    String? challengeId,
    Map<String, dynamic>? device,
  }) async {
    await _delay();
    if (otp == '1234' || otp == '123456') {
      return VerifyOtpResult(
        accessToken: 'mock_access_token',
        refreshToken: 'mock_refresh_token',
        user: UserModel(
          id: 'usr_${phone.hashCode.abs()}',
          name: '',
          phone: phone,
          email: null,
          role: UserRole.customer,
          isVerified: true,
        ),
        isNewUser: true,
      );
    }
    throw const ApiException(
      message: 'Invalid OTP. Please try again.',
      code: 'INVALID_OTP',
    );
  }

  @override
  Future<TokenPair> refreshTokens() async {
    return const TokenPair(
      accessToken: 'mock_access_token_refreshed',
      refreshToken: 'mock_refresh_token_refreshed',
    );
  }

  @override
  Future<void> logout() async {
    // No-op in mock mode
  }

  // ── Categories ────────────────────────────────────────────────────────────

  @override
  Future<List<CategoryModel>> getCategories() async {
    await _delay();
    final data = await _loadJson('categories');
    return (data as List)
        .map((e) => CategoryModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Banners ───────────────────────────────────────────────────────────────

  @override
  Future<List<BannerModel>> getBanners() async {
    await _delay();
    final data = await _loadJson('banners');
    return (data as List)
        .map((e) => BannerModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Vendors ───────────────────────────────────────────────────────────────

  @override
  Future<PaginatedResponse<VendorModel>> getVendors({
    String? categoryId,
    String? search,
    PaginationParams params = const PaginationParams(),
  }) async {
    await _delay();
    final data = await _loadJson('vendors');
    var vendors = (data as List)
        .map((e) => VendorModel.fromJson(e as Map<String, dynamic>))
        .toList();

    if (categoryId != null) {
      vendors =
          vendors.where((v) => v.categoryIds.contains(categoryId)).toList();
    }
    if (search != null && search.isNotEmpty) {
      final q = search.toLowerCase();
      vendors = vendors
          .where((v) =>
              v.name.toLowerCase().contains(q) ||
              v.description.toLowerCase().contains(q))
          .toList();
    }

    final total = vendors.length;
    final offset = (params.page - 1) * params.pageSize;
    final items = vendors.skip(offset).take(params.pageSize).toList();

    return PaginatedResponse(
      items: items,
      meta: PaginationMeta(
        currentPage: params.page,
        totalPages: (total / params.pageSize).ceil().clamp(1, 9999),
        totalItems: total,
        pageSize: params.pageSize,
      ),
    );
  }

  @override
  Future<VendorModel> getVendorById(String vendorId) async {
    await _delay();
    final data = await _loadJson('vendors');
    final json = (data as List).firstWhere(
      (e) => (e as Map<String, dynamic>)['id'] == vendorId,
      orElse: () => throw Exception('Vendor $vendorId not found'),
    );
    return VendorModel.fromJson(json as Map<String, dynamic>);
  }

  @override
  Future<List<ServiceModel>> getServicesByVendor(String vendorId) async {
    await _delay();
    final data = await _loadJson('services');
    return (data as List)
        .map((e) => ServiceModel.fromJson(e as Map<String, dynamic>))
        .where((s) => s.vendorId == vendorId)
        .toList();
  }

  // ── Cart ──────────────────────────────────────────────────────────────────

  // One cart per vendor — see ApiCustomerRepository.
  final Map<String, List<CartItem>> _cartsByVendor = {};
  String? _activeCartVendorId;

  @override
  String? get activeCartVendorId => _activeCartVendorId;

  @override
  void setActiveCartVendor(String? vendorId) {
    _activeCartVendorId =
        (vendorId == null || vendorId.isEmpty) ? null : vendorId;
  }

  @override
  Future<CartModel> getCart() async {
    await _delay(fast: true);
    return _buildCart();
  }

  @override
  Future<CartModel> addToCart({
    required String serviceId,
    required String vendorId,
    required int quantity,
  }) async {
    await _delay(fast: true);
    final items = _cartsByVendor.putIfAbsent(vendorId, () => []);
    final existing = items.indexWhere((i) => i.serviceId == serviceId);
    if (existing >= 0) {
      items[existing] = items[existing]
          .copyWith(quantity: items[existing].quantity + quantity);
    } else {
      items.add(CartItem(
        id: 'ci_${vendorId}_$serviceId',
        serviceId: serviceId,
        vendorId: vendorId,
        quantity: quantity,
      ));
    }
    _activeCartVendorId = vendorId;
    return _buildCart();
  }

  @override
  Future<CartModel> removeFromCart(String cartItemId) async {
    await _delay(fast: true);
    for (final items in _cartsByVendor.values) {
      items.removeWhere((i) => i.id == cartItemId);
    }
    return _buildCart();
  }

  @override
  Future<CartModel> updateCartItem({
    required String cartItemId,
    required int quantity,
  }) async {
    await _delay(fast: true);
    if (quantity <= 0) return removeFromCart(cartItemId);
    for (final items in _cartsByVendor.values) {
      final idx = items.indexWhere((i) => i.id == cartItemId);
      if (idx >= 0) {
        items[idx] = items[idx].copyWith(quantity: quantity);
        break;
      }
    }
    return _buildCart();
  }

  @override
  Future<void> clearCart() async {
    final id = _activeCartVendorId;
    if (id != null) _cartsByVendor[id]?.clear();
  }

  CartModel _buildCart() {
    final id = _activeCartVendorId;
    final items = id == null ? const <CartItem>[] : (_cartsByVendor[id] ?? const <CartItem>[]);
    return CartModel(items: List.unmodifiable(items));
  }

  // ── Orders ────────────────────────────────────────────────────────────────

  @override
  Future<PaginatedResponse<OrderModel>> getMyOrders({
    PaginationParams params = const PaginationParams(),
  }) async {
    await _delay();
    final data = await _loadJson('orders');
    final orders = (data as List)
        .map((e) => OrderModel.fromJson(e as Map<String, dynamic>))
        .toList();
    final total = orders.length;
    final offset = (params.page - 1) * params.pageSize;
    final items = orders.skip(offset).take(params.pageSize).toList();
    return PaginatedResponse(
      items: items,
      meta: PaginationMeta(
        currentPage: params.page,
        totalPages: (total / params.pageSize).ceil().clamp(1, 9999),
        totalItems: total,
        pageSize: params.pageSize,
      ),
    );
  }

  @override
  Future<OrderModel> getOrderById(String orderId) async {
    await _delay();
    final data = await _loadJson('orders');
    final json = (data as List).firstWhere(
      (e) => (e as Map<String, dynamic>)['id'] == orderId,
      orElse: () => throw Exception('Order $orderId not found'),
    );
    return OrderModel.fromJson(json as Map<String, dynamic>);
  }

  @override
  Future<List<OrderModel>> getMyStoreOrders() async {
    await _delay();
    return const [];
  }

  @override
  Future<OrderModel> placeOrder(PlaceOrderRequest request) async {
    await _delay();
    // Draft-based placement: return a sensible mock order
    if (request.orderDraftId != null && request.orderDraftId!.isNotEmpty) {
      return OrderModel(
        id: 'ord_${DateTime.now().millisecondsSinceEpoch}',
        customerId: 'usr_demo',
        vendorId: 'vndr_demo',
        items: [
          OrderItem(
              serviceId: 'svc_mock_1',
              serviceName: 'Wash & Fold',
              quantity: 3,
              unitPrice: 199,
              totalPrice: 597),
          OrderItem(
              serviceId: 'svc_mock_2',
              serviceName: 'Steam Iron',
              quantity: 5,
              unitPrice: 99,
              totalPrice: 495),
        ],
        status: OrderStatus.waitingForVendorConfirmation,
        subtotal: 1092.0,
        platformFee: 54.60,
        gstAmount: 196.56,
        total: 1343.16,
        paymentMethod: PaymentMethod.upi,
        pickupAddressId: 'addr_1',
        deliveryAddressId: 'addr_1',
        scheduledPickupAt: DateTime.now().add(const Duration(hours: 2)),
        createdAt: DateTime.now(),
      );
    }

    // Legacy direct placement
    return OrderModel(
      id: 'ord_${DateTime.now().millisecondsSinceEpoch}',
      customerId: 'usr_demo',
      vendorId: request.vendorId ?? 'vndr_demo',
      items: request.items
          .map((i) => OrderItem(
                serviceId: i.serviceId,
                serviceName: 'Service',
                quantity: i.quantity,
                unitPrice: 199,
                totalPrice: i.quantity * 199,
              ))
          .toList(),
      status: OrderStatus.waitingForVendorConfirmation,
      subtotal: request.items.fold(0.0, (s, i) => s + i.quantity * 199),
      platformFee:
          request.items.fold(0.0, (s, i) => s + i.quantity * 199) * 0.05,
      gstAmount: request.items.fold(0.0, (s, i) => s + i.quantity * 199) * 0.18,
      total: request.items.fold(0.0, (s, i) => s + i.quantity * 199) * 1.23,
      paymentMethod: request.paymentMethod ?? PaymentMethod.upi,
      pickupAddressId: request.pickupAddressId ?? 'addr_1',
      deliveryAddressId: request.deliveryAddressId ?? 'addr_1',
      scheduledPickupAt: request.scheduledPickupAt ??
          DateTime.now().add(const Duration(hours: 2)),
      customerNotes: request.notes,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<OrderModel> cancelOrder(String orderId, {String? reason}) async {
    await _delay();
    final order = await getOrderById(orderId);
    return order.copyWith(
      status: OrderStatus.customerCancelled,
      cancellationReason: reason,
      updatedAt: DateTime.now(),
    );
  }

  // ── Profile ───────────────────────────────────────────────────────────────

  UserModel _mockUser = const UserModel(
    id: 'usr_demo',
    name: 'Demo User',
    phone: '9876543210',
    email: 'demo@lndry.app',
    role: UserRole.customer,
    isVerified: true,
  );

  @override
  Future<UserModel> getProfile() async {
    await _delay(fast: true);
    return _mockUser;
  }

  @override
  Future<UpdateProfileResult> updateProfile(UpdateProfileRequest request) async {
    await _delay();
    _mockUser = _mockUser.copyWith(
      name: request.name ?? _mockUser.name,
      email: request.email ?? _mockUser.email,
      avatarUrl: request.avatarUrl ?? _mockUser.avatarUrl,
      updatedAt: DateTime.now(),
    );

    ReferralRedemptionResult? referralOutcome;
    final code = request.referralCode?.trim();
    if (code != null && code.isNotEmpty) {
      referralOutcome = code.toUpperCase() == 'INVALID'
          ? const ReferralRedemptionResult(
              success: false,
              code: 'REFERRAL_CODE_INVALID',
              message: "That referral code doesn't look right.",
            )
          : const ReferralRedemptionResult(success: true, redeemed: true);
    }

    return UpdateProfileResult(user: _mockUser, referralOutcome: referralOutcome);
  }

  // ── Addresses ─────────────────────────────────────────────────────────────

  final List<AddressModel> _addresses = [
    const AddressModel(
      id: 'addr_1',
      userId: 'usr_demo',
      line1: '42, MG Road',
      city: 'Bengaluru',
      state: 'Karnataka',
      pincode: '560001',
      type: AddressType.home,
      isDefault: true,
    ),
  ];

  Future<void> _saveAddressesToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _addresses.map((a) => a.toJson()).toList();
      await prefs.setString('mock_addresses', jsonEncode(jsonList));
    } catch (_) {}
  }

  Future<void> _loadAddressesFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dataStr = prefs.getString('mock_addresses');
      if (dataStr != null) {
        final decoded = jsonDecode(dataStr) as List<dynamic>;
        final loaded = decoded.map((item) => AddressModel.fromJson(item as Map<String, dynamic>)).toList();
        _addresses.clear();
        _addresses.addAll(loaded);
      }
    } catch (_) {}
  }

  @override
  Future<List<AddressModel>> getAddresses() async {
    await _delay(fast: true);
    await _loadAddressesFromStorage();
    return List.unmodifiable(_addresses);
  }

  @override
  Future<AddressModel> addAddress(AddressModel address) async {
    await _delay();
    await _loadAddressesFromStorage();
    final a = address.copyWith(
      id: 'addr_${DateTime.now().millisecondsSinceEpoch}',
      createdAt: DateTime.now(),
    );
    _addresses.add(a);
    await _saveAddressesToStorage();
    return a;
  }

  @override
  Future<AddressModel> updateAddress(AddressModel address) async {
    await _delay();
    await _loadAddressesFromStorage();
    final idx = _addresses.indexWhere((a) => a.id == address.id);
    if (idx >= 0) _addresses[idx] = address;
    await _saveAddressesToStorage();
    return address;
  }

  @override
  Future<void> deleteAddress(String addressId) async {
    await _delay(fast: true);
    await _loadAddressesFromStorage();
    _addresses.removeWhere((a) => a.id == addressId);
    await _saveAddressesToStorage();
  }

  @override
  Future<void> setDefaultAddress(String addressId) async {
    await _delay(fast: true);
    await _loadAddressesFromStorage();
    for (var i = 0; i < _addresses.length; i++) {
      _addresses[i] = _addresses[i].copyWith(
        isDefault: _addresses[i].id == addressId,
      );
    }
    await _saveAddressesToStorage();
  }

  // ── Search / Discovery ──────────────────────────────────────────────────

  @override
  Future<SearchResults> search({
    required String query,
    double? lat,
    double? lng,
  }) async {
    await _delay();
    // Return empty results in mock mode; search is a backend feature.
    return const SearchResults(
      categories: [],
      garmentTypes: [],
      vendors: [],
    );
  }

  @override
  Future<List<SearchSuggestion>> getSearchSuggestions(String query) async {
    await _delay(fast: true);
    return [];
  }

  @override
  Future<FilterOptions> getFilterOptions() async {
    await _delay(fast: true);
    return const FilterOptions(
      sortOptions: [
        SortOption(label: 'Nearest', value: 'nearest'),
        SortOption(label: 'Best Rating', value: 'best_rating'),
        SortOption(label: 'Price: Low to High', value: 'price_asc'),
        SortOption(label: 'Price: High to Low', value: 'price_desc'),
        SortOption(label: 'Value for Money', value: 'value_for_money'),
      ],
      garmentTypes: [],
    );
  }

  // ── Payments (mock) ───────────────────────────────────────────────────────

  @override
  Future<PaymentOrderResult> createPaymentOrder({
    String? orderId,
    String? orderDraftId,
  }) async {
    await _delay();
    return PaymentOrderResult(
      paymentId: 'pay_mock_${DateTime.now().millisecondsSinceEpoch}',
      razorpayOrderId:
          'rzp_mock_order_${DateTime.now().millisecondsSinceEpoch}',
      amount: 79900,
      currency: 'INR',
      keyId: 'rzp_mock_key',
    );
  }

  @override
  Future<PaymentVerificationResult> verifyPayment({
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
    String? orderDraftId,
  }) async {
    await _delay(fast: true);
    return const PaymentVerificationResult(
      success: true,
      paymentId: 'pay_mock_verified',
      razorpayPaymentId: 'rzp_pay_mock',
      orderId: 'ord_mock',
      status: 'VERIFIED',
    );
  }

  @override
  Future<PaymentStatusResult> getPaymentStatus({
    String? orderDraftId,
    String? orderId,
  }) async {
    await _delay(fast: true);
    return PaymentStatusResult(kind: PaymentStatusKind.paid, orderId: orderId ?? 'ord_mock');
  }

  // ── Wallet (mock) ─────────────────────────────────────────────────────────

  @override
  Future<WalletModel> getWallet() async {
    await _delay(fast: true);
    return const WalletModel(id: 'wallet_mock', balance: 250);
  }

  @override
  Future<List<WalletTransactionModel>> getWalletTransactions() async {
    await _delay(fast: true);
    final now = DateTime.now();
    return [
      WalletTransactionModel(
        id: 'wtx_mock_1',
        type: 'CREDIT',
        amount: 50,
        description: 'Referral reward',
        balanceAfter: 250,
        createdAt: now.subtract(const Duration(days: 1)),
      ),
      WalletTransactionModel(
        id: 'wtx_mock_2',
        type: 'DEBIT',
        amount: 30,
        description: 'Order advance payment',
        balanceAfter: 200,
        createdAt: now.subtract(const Duration(days: 3)),
      ),
    ];
  }

  @override
  Future<PendingWalletRedemption?> getPendingWalletRedemption() async {
    await _delay(fast: true);
    return null;
  }

  @override
  Future<WalletTopUpOrderResult> createWalletTopUp(double amount) async {
    await _delay();
    return WalletTopUpOrderResult(
      razorpayOrderId: 'rzp_mock_topup_${DateTime.now().millisecondsSinceEpoch}',
      amount: amount,
      currency: 'INR',
      keyId: 'rzp_mock_key',
    );
  }

  @override
  Future<WalletModel> verifyWalletTopUp({
    required String paymentId,
    required String orderId,
    required String signature,
  }) async {
    await _delay(fast: true);
    return const WalletModel(id: 'wallet_mock', balance: 250);
  }

  @override
  Future<WalletPaymentResult> payWithWallet({
    String? orderId,
    String? orderDraftId,
  }) async {
    await _delay(fast: true);
    return const WalletPaymentResult(success: true);
  }

  // ── Referrals (mock) ──────────────────────────────────────────────────────

  @override
  Future<ReferralSummary> getReferralSummary() async {
    await _delay(fast: true);
    return const ReferralSummary(
      referralCode: 'DEMO1234',
      totalReferred: 2,
      pending: 1,
      completed: 1,
      totalWalletEarned: 50,
      activeProgram: ReferralActiveProgram(
        name: 'Refer & Earn',
        referrerRewardType: 'WALLET_CREDIT',
        referrerRewardAmount: 50,
        refereeRewardType: 'WALLET_CREDIT',
        refereeRewardAmount: 50,
        termsText: 'You and your friend each get ₹50 in wallet credit once they complete their first order.',
      ),
    );
  }

  @override
  Future<List<ReferralHistoryItem>> getReferralHistory() async {
    await _delay(fast: true);
    final now = DateTime.now();
    return [
      ReferralHistoryItem(
        id: 'ref_mock_1',
        status: 'COMPLETED',
        refereeName: 'Priya',
        refereePhoneMasked: '••••••4321',
        refereeSignedUpAt: now.subtract(const Duration(days: 5)),
        refereeFirstOrderCompletedAt: now.subtract(const Duration(days: 3)),
        referrerRewardStatus: 'GRANTED',
        referrerRewardGrantedAt: now.subtract(const Duration(days: 3)),
      ),
      ReferralHistoryItem(
        id: 'ref_mock_2',
        status: 'PENDING_FIRST_ORDER',
        refereeName: 'Arjun',
        refereePhoneMasked: '••••••8765',
        refereeSignedUpAt: now.subtract(const Duration(days: 1)),
        referrerRewardStatus: 'PENDING',
      ),
    ];
  }

  // ── Pickup Slots (mock) ───────────────────────────────────────────────────

  @override
  Future<List<PickupSlot>> getPickupSlots({
    required String vendorId,
    required String date,
  }) async {
    await _delay();
    return [
      PickupSlot(
        id: 'slot_morning_1',
        vendorId: vendorId,
        date: date,
        startTime: '09:00',
        endTime: '10:00',
        label: 'Morning',
        remainingCapacity: 5,
        isActive: true,
      ),
      PickupSlot(
        id: 'slot_morning_2',
        vendorId: vendorId,
        date: date,
        startTime: '10:00',
        endTime: '11:00',
        label: 'Morning',
        remainingCapacity: 3,
        isActive: true,
      ),
      PickupSlot(
        id: 'slot_afternoon_1',
        vendorId: vendorId,
        date: date,
        startTime: '14:00',
        endTime: '15:00',
        label: 'Afternoon',
        remainingCapacity: 7,
        isActive: true,
      ),
      PickupSlot(
        id: 'slot_afternoon_2',
        vendorId: vendorId,
        date: date,
        startTime: '15:00',
        endTime: '16:00',
        label: 'Afternoon',
        remainingCapacity: 4,
        isActive: true,
      ),
      PickupSlot(
        id: 'slot_evening_1',
        vendorId: vendorId,
        date: date,
        startTime: '17:00',
        endTime: '18:00',
        label: 'Evening',
        remainingCapacity: 6,
        isActive: true,
      ),
    ];
  }

  @override
  Future<SlotHoldResult> holdSlot({
    required String vendorId,
    required String slotId,
    required String date,
    String? quoteId,
  }) async {
    await _delay(fast: true);
    return SlotHoldResult(
      holdId: 'hold_${DateTime.now().millisecondsSinceEpoch}',
      slotId: slotId,
      expiresAt: DateTime.now().add(const Duration(minutes: 10)),
    );
  }

  @override
  Future<void> releaseSlotHold(String holdId) async {
    await _delay(fast: true);
    // No-op in mock mode
  }

  // ── Order Draft (mock) ─────────────────────────────────────────────────────

  @override
  Future<QuoteResult> createQuote({
    required String vendorId,
    String? vendorServiceId,
    required List<QuoteGarmentLine> garmentLines,
    double? estimatedWeightKg,
    bool assisted = false,
    String? addressId,
  }) async {
    await _delay(fast: true);
    if (assisted) {
      return QuoteResult(
        quoteId: 'quote_assisted_${DateTime.now().millisecondsSinceEpoch}',
        estimatePaise: 0,
        expiresAt: DateTime.now().add(const Duration(minutes: 10)),
      );
    }
    final estimatedPaise = garmentLines.fold<int>(
      0,
      (sum, line) => sum + (line.quantity * 19900),
    );
    return QuoteResult(
      quoteId: 'quote_${DateTime.now().millisecondsSinceEpoch}',
      estimatePaise: estimatedPaise == 0 ? 59900 : estimatedPaise,
      expiresAt: DateTime.now().add(const Duration(minutes: 10)),
    );
  }

  @override
  Future<OrderDraftResult> prepareOrder({
    required String quoteId,
    required String addressId,
    String? slotId,
    bool isExpressPickup = false,
    String? couponCode,
  }) async {
    await _delay();
    return OrderDraftResult(
      orderDraftId: 'draft_${DateTime.now().millisecondsSinceEpoch}',
      payableAmountPaise: 79900, // ₹799.00
      snapshot: {
        'subtotal': 59900,
        'delivery_fee': 5000,
        'tax': 10000,
        'total': 79900,
        'items': [
          {
            'name': 'Wash & Fold',
            'quantity': 3,
            'unit_price': 9900,
            'total': 29700
          },
          {
            'name': 'Steam Iron',
            'quantity': 5,
            'unit_price': 4900,
            'total': 24500
          },
        ],
      },
    );
  }

  @override
  Future<CouponValidationResult> validateCoupon({
    required String code,
    required double cartTotal,
  }) async {
    await _delay();
    if (code.trim().toUpperCase() == 'LNDRY20') {
      final discount = (cartTotal * 0.20).clamp(0, 100).toDouble();
      return CouponValidationResult(valid: true, discount: discount, code: 'LNDRY20');
    }
    return const CouponValidationResult(valid: false, message: 'Coupon not found');
  }

  @override
  Future<List<CartMilestoneTier>> getActiveCartMilestoneTiers() async {
    await _delay();
    return const [
      CartMilestoneTier(
        id: 'mock-tier-1',
        name: 'Flat ₹20 off',
        minOrderAmount: 99,
        rewardType: 'FLAT_DISCOUNT',
        rewardValue: 20,
      ),
      CartMilestoneTier(
        id: 'mock-tier-2',
        name: 'Flat ₹50 off',
        minOrderAmount: 199,
        rewardType: 'FLAT_DISCOUNT',
        rewardValue: 50,
      ),
      CartMilestoneTier(
        id: 'mock-tier-3',
        name: 'Unlock 10% off coupon',
        minOrderAmount: 299,
        rewardType: 'COUPON_UNLOCK',
      ),
    ];
  }

  @override
  Future<List<CouponSummary>> getAvailableCoupons() async {
    await _delay();
    return [
      CouponSummary(
        id: 'mock-coupon-1',
        code: 'LNDRY20',
        description: 'Flat 20% off on your order',
        discountType: 'PERCENTAGE',
        discountValue: 20,
        minOrderAmount: 199,
        maxDiscount: 100,
        validUntil: DateTime.now().add(const Duration(days: 30)),
        terms: 'Valid on orders above ₹199. Maximum discount ₹100.',
      ),
      CouponSummary(
        id: 'mock-coupon-2',
        code: 'FLAT50',
        description: 'Flat ₹50 off',
        discountType: 'FLAT',
        discountValue: 50,
        minOrderAmount: 299,
        validUntil: DateTime.now().add(const Duration(days: 15)),
        terms: 'Valid on orders above ₹299.',
      ),
    ];
  }

  @override
  Future<FirstTimeOfferResult> getActiveFirstTimeOffer() async {
    await _delay();
    return const FirstTimeOfferResult(
      eligible: true,
      tiers: [
        CartMilestoneTier(
          id: 'mock-fto-1',
          name: '15% off your first order',
          minOrderAmount: 0,
          rewardType: 'PERCENTAGE_DISCOUNT',
          rewardValue: 15,
          maxDiscount: 150,
        ),
      ],
    );
  }

  // ── User Stats (mock) ───────────────────────────────────────────────────

  @override
  Future<UserStats> getUserStats() async {
    await _delay();
    return const UserStats(
      totalOrders: 12,
      totalSpent: 7590.50,
      loyaltyPoints: 240,
    );
  }

  // ── Reviews (mock) ────────────────────────────────────────────────────────

  @override
  Future<PaginatedResponse<ReviewModel>> getVendorReviews(
    String vendorId, {
    PaginationParams params = const PaginationParams(),
  }) async {
    await _delay();
    return PaginatedResponse(
      items: [
        ReviewModel(
          id: 'rev_1',
          userId: 'usr_demo',
          orderId: 'ord_1',
          vendorId: vendorId,
          vendorRating: 5,
          comment: 'Excellent service! Clothes came back spotless and crisp.',
          createdAt: DateTime.now().subtract(const Duration(days: 2)),
          userName: 'Aarav S.',
        ),
        ReviewModel(
          id: 'rev_2',
          userId: 'usr_demo2',
          orderId: 'ord_2',
          vendorId: vendorId,
          vendorRating: 4,
          comment: 'Very happy with the quality and on-time pickup.',
          createdAt: DateTime.now().subtract(const Duration(days: 5)),
          userName: 'Neha R.',
        ),
      ],
      meta: const PaginationMeta(
        currentPage: 1,
        totalPages: 1,
        totalItems: 2,
        pageSize: 20,
      ),
    );
  }

  @override
  Future<PaginatedResponse<ReviewModel>> getMyReviews({
    PaginationParams params = const PaginationParams(),
  }) async {
    await _delay();
    return PaginatedResponse(
      items: const [],
      meta: PaginationMeta(
        currentPage: 1,
        totalPages: 1,
        totalItems: 0,
        pageSize: params.pageSize,
      ),
    );
  }

  @override
  Future<ReviewModel> createReview({
    required String orderId,
    required int vendorRating,
    int? riderRating,
    String? comment,
  }) async {
    await _delay();
    return ReviewModel(
      id: 'rev_${DateTime.now().millisecondsSinceEpoch}',
      userId: 'usr_demo',
      orderId: orderId,
      vendorId: 'vndr_demo',
      vendorRating: vendorRating,
      riderRating: riderRating,
      comment: comment,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<ReviewModel> updateReview(
    String reviewId, {
    int? vendorRating,
    int? riderRating,
    String? comment,
  }) async {
    await _delay();
    return ReviewModel(
      id: reviewId,
      userId: 'usr_demo',
      orderId: 'ord_1',
      vendorId: 'vndr_demo',
      vendorRating: vendorRating ?? 5,
      riderRating: riderRating,
      comment: comment,
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> deleteReview(String reviewId) async {
    await _delay(fast: true);
  }

  @override
  Future<bool> hasReviewedOrder(String orderId) async {
    await _delay(fast: true);
    return false;
  }

  // ── Order Actions (mock) ─────────────────────────────────────────────────

  @override
  Future<ReorderResult> reorder(String orderId) async {
    await _delay();
    final original = await getOrderById(orderId);
    return ReorderResult(
      success: true,
      message: 'Items added for reorder.',
      itemCount: original.items.length,
    );
  }

  @override
  Future<InvoiceInfo> getOrderInvoice(String orderId) async {
    await _delay();
    return InvoiceInfo(
      id: 'inv_mock',
      invoiceNumber: 'INV-2627-000001',
      orderId: orderId,
      viewUrl: 'https://lndry.app/invoices/mock_$orderId.pdf',
      downloadUrl: 'https://lndry.app/invoices/mock_$orderId.pdf?download=1',
      invoiceDate: DateTime.now(),
      total: 736.77,
      paymentStatus: 'PAID',
    );
  }

  @override
  Future<OtpResult> getOrderOtp(
    String orderId, {
    required String purpose,
  }) async {
    await _delay();
    return OtpResult(
      otp: '123456',
      expiresAt: DateTime.now().add(const Duration(minutes: 10)),
      type: purpose.toLowerCase(),
      isVerified: false,
    );
  }

  // ── Notification Preferences (mock) ───────────────────────────────────────

  NotificationPreferences _notificationPrefs = const NotificationPreferences();

  @override
  Future<NotificationPreferences> getNotificationPreferences() async {
    await _delay(fast: true);
    return _notificationPrefs;
  }

  @override
  Future<NotificationPreferences> updateNotificationPreferences({
    bool? orderUpdates,
    bool? promotions,
    bool? newProducts,
    bool? deliveryUpdates,
    bool? priceDrops,
  }) async {
    await _delay();
    _notificationPrefs = NotificationPreferences(
      orderUpdates: orderUpdates ?? _notificationPrefs.orderUpdates,
      promotions: promotions ?? _notificationPrefs.promotions,
      newProducts: newProducts ?? _notificationPrefs.newProducts,
      deliveryUpdates: deliveryUpdates ?? _notificationPrefs.deliveryUpdates,
      priceDrops: priceDrops ?? _notificationPrefs.priceDrops,
    );
    return _notificationPrefs;
  }

  // ── Avatar (mock) ─────────────────────────────────────────────────────────

  @override
  Future<String> uploadAvatar(String filePath) async {
    await _delay();
    return 'https://via.placeholder.com/150?text=Avatar';
  }

  // ── Notifications ─────────────────────────────────────────────────────────

  @override
  Future<List<NotificationModel>> getNotifications({
    PaginationParams params = const PaginationParams(),
  }) async {
    await _delay(fast: true);
    return [];
  }

  @override
  Future<void> markNotificationRead(String notificationId) async {}

  @override
  Future<void> markAllNotificationsRead() async {}

  @override
  Future<void> deleteNotification(String notificationId) async {
    await _delay(fast: true);
  }

  @override
  Future<void> registerDevice({
    required String deviceId,
    required String platform,
    required String fcmToken,
    String? appVersion,
    String? deviceModel,
  }) async {
    await _delay(fast: true);
  }

  @override
  Future<void> unregisterDevice(String deviceId, {String? fcmToken}) async {
    await _delay(fast: true);
  }

  @override
  Future<void> reportNotificationOpened({
    String? deliveryId,
    String? notificationId,
    String? campaignId,
  }) async {}

  @override
  Future<SupportContact> getSupportContact() async {
    await _delay(fast: true);
    return const SupportContact(phone: '+919775845587', email: 'support@lndryapp.com');
  }

  AccountDeletionRequest? _mockDeletionRequest;

  @override
  Future<StoreOrderDetail?> findStoreOrder(String id) async {
    await _delay(fast: true);
    return null;
  }

  @override
  Future<List<FaqItem>> getFaqs() async {
    await _delay(fast: true);
    return const [
      FaqItem(
        id: '1',
        question: 'What is the turnaround time for delivery?',
        answer:
            'Most of our laundry vendors return clothes clean, folded, and ironed within 24 to 48 hours. Estimated delivery dates are shown on your order tracking timeline.',
      ),
      FaqItem(
        id: '2',
        question: 'How do I pay for my order?',
        answer:
            'LNDRY supports completely secure cashless payments using our built-in Razorpay gateway. You can pay via UPI (GPay, Paytm), Cards, Net Banking, or choose Cash on Delivery.',
      ),
    ];
  }

  @override
  Future<AccountDeletionRequest?> getAccountDeletionRequest() async {
    await _delay(fast: true);
    return _mockDeletionRequest;
  }

  @override
  Future<AccountDeletionRequest> requestAccountDeletion({String? reason}) async {
    await _delay(fast: true);
    return _mockDeletionRequest = AccountDeletionRequest(
      id: 'mock-deletion',
      status: 'PENDING',
      requestedAt: DateTime.now(),
    );
  }

  @override
  Future<AssistedBookingConfig> getAssistedBookingConfig(String vendorId) async {
    await _delay(fast: true);
    // The mock build shows the option so the flow can be reviewed visually.
    return const AssistedBookingConfig(
      available: true,
      title: 'Not sure what service you need?',
      subtitle:
          "Book now — we'll inspect your garments and confirm the right service & price.",
      buttonText: 'Book With Expert Check',
      checkoutNote:
          'Service & final price will be confirmed after garment inspection.',
      assessmentTitle: 'Laundry Assessment Required',
      assessmentMessage:
          'Vendor will inspect your garments and confirm services, quantity/weight and final price.',
      priceLabel: 'Price after inspection',
    );
  }

  @override
  Future<CheckoutContent> getCheckoutContent() async {
    await _delay(fast: true);
    return CheckoutContent.fallback;
  }

  // ── Order Reconciliation ──────────────────────────────────────────────────
  @override
  Future<OrderReconciliationModel?> getOrderReconciliation(String orderId) async {
    await _delay(fast: true);
    return null;
  }

  @override
  Future<void> acceptOrderReconciliation(String orderId) async {
    await _delay(fast: true);
  }

  @override
  Future<void> rejectOrderReconciliation(String orderId, {String? reason}) async {
    await _delay(fast: true);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<dynamic> _loadJson(String name) async {
    final raw = await rootBundle.loadString('assets/mock/$name.json');
    return json.decode(raw);
  }

  Future<void> _delay({bool fast = false}) =>
      Future.delayed(Duration(milliseconds: fast ? 200 : 600));
}

final useMocksProvider = StateProvider<bool>((ref) {
  return Env.useMocksForVisualTestsOnly || Env.demoMode;
});

final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  final useMocks = ref.watch(useMocksProvider);
  if (useMocks) {
    return MockCustomerRepository();
  }
  final dio = ref.watch(dioClientProvider);
  final storage = ref.watch(storageServiceProvider);
  return ApiCustomerRepository(dio: dio, storage: storage);
});
