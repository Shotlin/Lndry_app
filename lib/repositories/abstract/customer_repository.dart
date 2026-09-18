import 'dart:typed_data';

import '../../models/models.dart';
import '../../shared/repositories/base_repository.dart';

/// Abstract contract for all customer-facing data operations.
/// Swap [MockCustomerRepository] → [ApiCustomerRepository] when backend is ready.
abstract interface class CustomerRepository {
  // ── Auth ────────────────────────────────────────────────────────────────────
  /// Request an OTP for [phone]. Returns challenge metadata.
  /// In dev mode [devOtp] may contain the OTP for quick testing.
  Future<SendOtpResult> sendOtp(String phone);

  /// Verify [otp] received for [phone] against the optional [challengeId].
  /// On success returns tokens and user profile.
  Future<VerifyOtpResult> verifyOtp({
    required String phone,
    required String otp,
    String? challengeId,
    Map<String, dynamic>? device,
  });

  /// Refresh the access + refresh token pair.
  Future<TokenPair> refreshTokens();

  /// Invalidate the current refresh token on the server and clear local state.
  Future<void> logout();

  // ── Services / Categories ─────────────────────────────────────────────────
  Future<List<CategoryModel>> getCategories();

  // ── Banners ──────────────────────────────────────────────────────────────
  /// Get active promotional banners (Home carousel / popups / announcements).
  Future<List<BannerModel>> getBanners();

  Future<PaginatedResponse<VendorModel>> getVendors({
    String? categoryId,
    String? search,
    PaginationParams params,
  });

  Future<VendorModel> getVendorById(String vendorId);

  Future<List<ServiceModel>> getServicesByVendor(String vendorId);

  // ── Cart ──────────────────────────────────────────────────────────────────
  Future<CartModel> getCart();
  Future<CartModel> addToCart(
      {required String serviceId,
      required String vendorId,
      required int quantity});
  Future<CartModel> removeFromCart(String cartItemId);
  Future<CartModel> updateCartItem(
      {required String cartItemId, required int quantity});
  Future<void> clearCart();

  // ── Orders ────────────────────────────────────────────────────────────────
  Future<PaginatedResponse<OrderModel>> getMyOrders({PaginationParams params});
  Future<OrderModel> getOrderById(String orderId);

  /// Read-only "Laundry Store" (in-person counter sale) history — pushed
  /// by a vendor's own POS app when the buyer's phone matched this account.
  Future<List<OrderModel>> getMyStoreOrders();
  Future<OrderModel> placeOrder(PlaceOrderRequest request);
  Future<OrderModel> cancelOrder(String orderId, {String? reason});

  // ── Profile ───────────────────────────────────────────────────────────────
  Future<UserModel> getProfile();
  Future<UpdateProfileResult> updateProfile(UpdateProfileRequest request);

  // ── Addresses ─────────────────────────────────────────────────────────────
  Future<List<AddressModel>> getAddresses();
  Future<AddressModel> addAddress(AddressModel address);
  Future<AddressModel> updateAddress(AddressModel address);
  Future<void> deleteAddress(String addressId);
  Future<void> setDefaultAddress(String addressId);

  // ── Search / Discovery ──────────────────────────────────────────────────
  /// Unified search across categories, garment types, and vendors.
  Future<SearchResults> search({
    required String query,
    double? lat,
    double? lng,
  });

  /// Autocomplete suggestions for the search bar.
  Future<List<SearchSuggestion>> getSearchSuggestions(String query);

  /// Get available filter options (sort options, garment types).
  Future<FilterOptions> getFilterOptions();

  // ── Pickup Slots ──────────────────────────────────────────────────────────
  /// Get available pickup slots for a vendor on a given date.
  /// Returns only slots with remaining capacity > 0.
  Future<List<PickupSlot>> getPickupSlots({
    required String vendorId,
    required String date,
  });

  /// Hold a pickup slot for 10 minutes.
  Future<SlotHoldResult> holdSlot({
    required String vendorId,
    required String slotId,
    required String date,
    String? quoteId,
  });

  /// Release a previously held slot.
  Future<void> releaseSlotHold(String holdId);

  // ── Order Draft / Quote ─────────────────────────────────────────────────----
  /// Create a backend quotation before holding a slot and preparing checkout.
  /// [vendorServiceId] is informational only — a single quote/cart can span
  /// more than one of this vendor's services (e.g. mixing a per-kg wash
  /// line with a per-piece dry-clean line), so it's no longer required to
  /// be the same for every line and may be omitted entirely.
  Future<QuoteResult> createQuote({
    required String vendorId,
    String? vendorServiceId,
    required List<QuoteGarmentLine> garmentLines,
    double? estimatedWeightKg,
  });

  /// Prepare an order draft before payment. Returns the draft ID and payable amount.
  Future<OrderDraftResult> prepareOrder({
    required String quoteId,
    required String addressId,
    String? slotId,
    bool isExpressPickup = false,
    String? couponCode,
  });

  /// Validate a coupon code against the current cart subtotal (rupees).
  /// Returns the discount (rupees) the backend would apply.
  Future<CouponValidationResult> validateCoupon({
    required String code,
    required double cartTotal,
  });

  /// Active "milestone perks" tiers for the current customer (admin-configured
  /// Cart Milestones) — applies to every order, not just a first one; the
  /// backend already filters out tiers this customer isn't eligible for
  /// (usage limit reached, wrong segment, etc).
  Future<List<CartMilestoneTier>> getActiveCartMilestoneTiers();

  /// Coupons the current customer can currently use (targeting-eligible),
  /// for the dedicated Coupons & Offers page.
  Future<List<CouponSummary>> getAvailableCoupons();

  /// Whether the current customer still qualifies for a first-order offer,
  /// and which reward tiers are active — for the same Offers page.
  Future<FirstTimeOfferResult> getActiveFirstTimeOffer();

  // ── Payments ──────────────────────────────────────────────────────────────
  /// Create a Razorpay payment order for an existing order or order draft.
  Future<PaymentOrderResult> createPaymentOrder({
    String? orderId,
    String? orderDraftId,
  });

  /// Verify a Razorpay payment signature.
  Future<PaymentVerificationResult> verifyPayment({
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
    String? orderDraftId,
  });

  // ── Wallet ─────────────────────────────────────────────────────────────────
  /// Current wallet balance.
  Future<WalletModel> getWallet();

  /// Wallet transaction history, most recent first.
  Future<List<WalletTransactionModel>> getWalletTransactions();

  /// A vendor's own POS counter proposing to redeem part of this wallet's
  /// balance against an in-person sale, if one is currently pending.
  Future<PendingWalletRedemption?> getPendingWalletRedemption();

  /// Step 1: create a Razorpay order to top up the wallet.
  Future<WalletTopUpOrderResult> createWalletTopUp(double amount);

  /// Step 2: verify the top-up payment and credit the wallet.
  Future<WalletModel> verifyWalletTopUp({
    required String paymentId,
    required String orderId,
    required String signature,
  });

  /// Pay a draft's advance, or an existing order's balance, straight from
  /// wallet balance — an alternative to the Razorpay create+verify round
  /// trip for [createPaymentOrder]/[verifyPayment].
  Future<WalletPaymentResult> payWithWallet({
    String? orderId,
    String? orderDraftId,
  });

  // ── Referrals (Refer & Earn) ────────────────────────────────────────────────
  /// The current customer's own referral code, stats, and the terms of
  /// whichever active program currently applies to them as a referrer.
  Future<ReferralSummary> getReferralSummary();

  /// Every person this customer has referred, most recent first.
  Future<List<ReferralHistoryItem>> getReferralHistory();

  // ── Order Actions ─────────────────────────────────────────────────────────
  /// Reorder a previous order.
  Future<ReorderResult> reorder(String orderId);

  /// Get invoice for an order.
  Future<InvoiceResult> getOrderInvoice(String orderId);

  /// Get pickup or delivery OTP for an order.
  Future<OtpResult> getOrderOtp(String orderId, {required String purpose});

  // ── User Stats ──────────────────────────────────────────────────────────────
  /// Get user statistics (total orders, total spent, loyalty points).
  Future<UserStats> getUserStats();

  // ── Reviews ─────────────────────────────────────────────────────────────────
  /// Get reviews for a vendor.
  Future<PaginatedResponse<ReviewModel>> getVendorReviews(String vendorId,
      {PaginationParams params});

  /// Get the current user's own reviews.
  Future<PaginatedResponse<ReviewModel>> getMyReviews(
      {PaginationParams params});

  /// Create a review for an order (vendor rating).
  Future<ReviewModel> createReview({
    required String orderId,
    required int vendorRating,
    int? riderRating,
    String? comment,
  });

  /// Update an existing review.
  Future<ReviewModel> updateReview(
    String reviewId, {
    int? vendorRating,
    int? riderRating,
    String? comment,
  });

  /// Delete a review.
  Future<void> deleteReview(String reviewId);

  /// Whether the current user has already reviewed this order.
  Future<bool> hasReviewedOrder(String orderId);

  // ── Notifications ─────────────────────────────────────────────────────────
  Future<List<NotificationModel>> getNotifications({PaginationParams params});
  Future<void> markNotificationRead(String notificationId);
  Future<void> markAllNotificationsRead();
  Future<void> deleteNotification(String notificationId);

  // ── Device Registration ───────────────────────────────────────────────
  Future<void> registerDevice({
    required String deviceId,
    required String platform,
    required String fcmToken,
    String? appVersion,
  });

  Future<void> unregisterDevice(String deviceId);

  // ── Notification Preferences ────────────────────────────────────────────────
  Future<NotificationPreferences> getNotificationPreferences();
  Future<NotificationPreferences> updateNotificationPreferences({
    bool? orderUpdates,
    bool? promotions,
    bool? newProducts,
    bool? deliveryUpdates,
    bool? priceDrops,
  });

  // ── Avatar ──────────────────────────────────────────────────────────────────
  /// Upload a profile avatar image. Returns the URL of the uploaded image.
  Future<String> uploadAvatar(String filePath);

  // ── Support ─────────────────────────────────────────────────────────────────
  /// The real customer-support phone/email — used for both the Help page's
  /// "Call Us" action and the order-revision reject flow's "Talk to Support".
  Future<SupportContact> getSupportContact();

  // ── Order Reconciliation ──────────────────────────────────────────────────
  /// The vendor's proposed recalculation currently awaiting this customer's
  /// decision, or null if there isn't one. Also returns the last one shown
  /// even after a decision, until a newer proposal replaces it.
  Future<OrderReconciliationModel?> getOrderReconciliation(String orderId);

  /// Accepts the pending reconciliation — order proceeds to processing with
  /// the previously-shown proposed total applied verbatim.
  Future<void> acceptOrderReconciliation(String orderId);

  /// Rejects the pending reconciliation — order pauses in a disputed state;
  /// resolution is a manual support call, not another automated flow.
  Future<void> rejectOrderReconciliation(String orderId, {String? reason});
}

class SupportContact {
  const SupportContact({this.phone, this.email});

  final String? phone;
  final String? email;
}

// ── Search Result Types ───────────────────────────────────────────────────────-

class SearchResults {
  const SearchResults({
    required this.categories,
    required this.garmentTypes,
    required this.vendors,
  });

  final List<CategoryModel> categories;
  final List<SearchGarmentType> garmentTypes;
  final List<VendorModel> vendors;
}

class SearchGarmentType {
  const SearchGarmentType({
    required this.id,
    required this.name,
    this.slug,
    this.unit,
  });

  final String id;
  final String name;
  final String? slug;
  final String? unit;
}

class SearchSuggestion {
  const SearchSuggestion({
    required this.type,
    required this.text,
  });

  /// 'category', 'garment_type', or 'vendor'
  final String type;
  final String text;
}

class FilterOptions {
  const FilterOptions({
    required this.sortOptions,
    required this.garmentTypes,
  });

  final List<SortOption> sortOptions;
  final List<SearchGarmentType> garmentTypes;
}

class SortOption {
  const SortOption({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;
}

// ── Quote Types ──────────────────────────────────────────────────────────────

class QuoteGarmentLine {
  const QuoteGarmentLine({
    required this.garmentTypeId,
    required this.quantity,
  });

  final String garmentTypeId;
  final int quantity;
}

class QuoteResult {
  const QuoteResult({
    required this.quoteId,
    required this.estimatePaise,
    this.expiresAt,
  });

  final String quoteId;
  final int estimatePaise;
  final DateTime? expiresAt;
}

// ── Auth Result Types ─────────────────────────────────────────────────────────

class SendOtpResult {
  const SendOtpResult({
    required this.challengeId,
    required this.expiresIn,
    this.devOtp,
  });

  /// Unique challenge identifier returned by the backend.
  final String challengeId;

  /// OTP expiry in seconds (typically 300).
  final int expiresIn;

  /// Only populated in development mode — the actual OTP value.
  /// Null in production/staging (OTP is sent via SMS).
  final String? devOtp;
}

class VerifyOtpResult {
  const VerifyOtpResult({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
    required this.isNewUser,
  });

  final String accessToken;
  final String refreshToken;
  final UserModel user;

  /// True when this is the user's first login and they need profile setup.
  final bool isNewUser;
}

class TokenPair {
  const TokenPair({
    required this.accessToken,
    required this.refreshToken,
  });

  final String accessToken;
  final String refreshToken;
}

// ── Payment Types ────────────────────────────────────────────────────────────

/// Result of creating a Razorpay payment order.
class PaymentOrderResult {
  const PaymentOrderResult({
    required this.paymentId,
    required this.razorpayOrderId,
    required this.amount,
    required this.currency,
    this.keyId,
  });

  final String paymentId;
  final String razorpayOrderId;
  final double amount;
  final String currency;
  final String? keyId;
}

/// Result of verifying a Razorpay payment.
class PaymentVerificationResult {
  const PaymentVerificationResult({
    required this.success,
    this.paymentId,
    this.razorpayPaymentId,
    this.orderId,
    this.status,
  });

  final bool success;
  final String? paymentId;
  final String? razorpayPaymentId;
  final String? orderId;
  final String? status;
}

// ── Wallet Types ─────────────────────────────────────────────────────────────

/// Current wallet balance.
class WalletModel {
  const WalletModel({required this.id, required this.balance});

  final String id;
  final double balance;
}

/// A wallet redemption a vendor's POS has proposed against this customer's
/// real balance, awaiting the customer to read the code back to the
/// vendor. See Lndry_backend's wallet-redemption module (migration 112).
class PendingWalletRedemption {
  const PendingWalletRedemption({
    required this.requestId,
    required this.amountPaise,
    required this.vendorName,
    required this.otp,
    required this.expiresAt,
    required this.attemptsRemaining,
  });

  final String requestId;
  final int amountPaise;
  final String vendorName;

  /// The one-time code to read aloud to the vendor — null only in the
  /// unlikely case the server-side Redis copy already expired separately
  /// from the request row itself.
  final String? otp;
  final DateTime expiresAt;
  final int attemptsRemaining;

  double get amount => amountPaise / 100;
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  factory PendingWalletRedemption.fromJson(Map<String, dynamic> json) {
    return PendingWalletRedemption(
      requestId: json['requestId'] as String? ?? '',
      amountPaise: (json['amountPaise'] as num?)?.toInt() ?? 0,
      vendorName: json['vendorName'] as String? ?? 'the store',
      otp: json['otp'] as String?,
      expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? '') ??
          DateTime.now(),
      attemptsRemaining: (json['attemptsRemaining'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A single wallet ledger entry.
class WalletTransactionModel {
  const WalletTransactionModel({
    required this.id,
    required this.type,
    required this.amount,
    required this.description,
    required this.createdAt,
    this.balanceAfter,
  });

  final String id;

  /// 'CREDIT' or 'DEBIT'.
  final String type;
  final double amount;
  final String description;
  final DateTime createdAt;
  final double? balanceAfter;

  bool get isCredit => type == 'CREDIT';
}

/// Result of creating a Razorpay order for a wallet top-up.
class WalletTopUpOrderResult {
  const WalletTopUpOrderResult({
    required this.razorpayOrderId,
    required this.amount,
    required this.currency,
    this.keyId,
  });

  final String razorpayOrderId;
  final double amount;
  final String currency;
  final String? keyId;
}

/// Result of paying a draft's advance / an order's balance from wallet.
class WalletPaymentResult {
  const WalletPaymentResult({required this.success, this.message});

  final bool success;
  final String? message;
}

// ── Referral Types ───────────────────────────────────────────────────────────

/// The active program's terms, as they apply to the current customer
/// specifically as a referrer (server-resolved — mirrors exactly what
/// redeeming right now would actually grant).
class ReferralActiveProgram {
  const ReferralActiveProgram({
    required this.name,
    required this.referrerRewardType,
    this.referrerRewardAmount,
    this.referrerRewardCount,
    required this.refereeRewardType,
    this.refereeRewardAmount,
    this.refereeRewardCount,
    this.termsText,
  });

  final String name;
  final String referrerRewardType;
  final double? referrerRewardAmount;
  final int? referrerRewardCount;
  final String refereeRewardType;
  final double? refereeRewardAmount;
  final int? refereeRewardCount;
  final String? termsText;
}

/// The current customer's own referral code, stats, and active program.
class ReferralSummary {
  const ReferralSummary({
    required this.referralCode,
    required this.totalReferred,
    required this.pending,
    required this.completed,
    required this.totalWalletEarned,
    this.activeProgram,
  });

  final String? referralCode;
  final int totalReferred;
  final int pending;
  final int completed;
  final double totalWalletEarned;
  final ReferralActiveProgram? activeProgram;
}

/// One entry in "who I've referred" — refereeName/Phone are already
/// masked/first-name-only by the backend, safe to show as-is.
class ReferralHistoryItem {
  const ReferralHistoryItem({
    required this.id,
    required this.status,
    this.refereeName,
    this.refereePhoneMasked,
    required this.refereeSignedUpAt,
    this.refereeFirstOrderCompletedAt,
    required this.referrerRewardStatus,
    this.referrerRewardGrantedAt,
  });

  final String id;

  /// 'PENDING_FIRST_ORDER' or 'COMPLETED'.
  final String status;
  final String? refereeName;
  final String? refereePhoneMasked;
  final DateTime refereeSignedUpAt;
  final DateTime? refereeFirstOrderCompletedAt;

  /// 'NOT_APPLICABLE' | 'PENDING' | 'GRANTED' | 'FAILED'.
  final String referrerRewardStatus;
  final DateTime? referrerRewardGrantedAt;
}

// ── Pickup Slot Types ────────────────────────────────────────────────────────

/// A pickup slot returned by the backend.
class PickupSlot {
  const PickupSlot({
    required this.id,
    required this.vendorId,
    required this.date,
    required this.startTime,
    required this.endTime,
    this.label,
    required this.remainingCapacity,
    required this.isActive,
  });

  final String id;
  final String vendorId;
  final String date; // 'YYYY-MM-DD'
  final String startTime; // '09:00'
  final String endTime; // '10:00'
  final String? label; // e.g. 'Morning slot'
  final int remainingCapacity;
  final bool isActive;
}

/// Result of a successful slot hold.
class SlotHoldResult {
  const SlotHoldResult({
    required this.holdId,
    required this.slotId,
    this.expiresAt,
  });

  final String holdId;
  final String slotId;
  final DateTime? expiresAt;
}

/// Result of POST /orders/prepare.
class OrderDraftResult {
  const OrderDraftResult({
    required this.orderDraftId,
    required this.payableAmountPaise,
    this.snapshot,
  });

  final String orderDraftId;
  final int payableAmountPaise;
  final Map<String, dynamic>? snapshot;
}

/// Result of POST /coupons/validate.
class CouponValidationResult {
  const CouponValidationResult({
    required this.valid,
    this.discount = 0,
    this.message,
    this.code,
  });

  final bool valid;
  final double discount;
  final String? message;
  final String? code;
}

/// One tier of GET /cart-milestones/active.
class CartMilestoneTier {
  const CartMilestoneTier({
    required this.id,
    required this.name,
    required this.minOrderAmount,
    required this.rewardType,
    this.rewardValue,
    this.maxDiscount,
    this.messageBefore,
    this.messageAfter,
  });

  final String id;
  final String name;
  final double minOrderAmount;

  /// One of FLAT_DISCOUNT / COUPON_UNLOCK.
  final String rewardType;
  final double? rewardValue;
  final double? maxDiscount;

  /// Admin-authored copy, e.g. "Add {amount} more to unlock 10% off" — the
  /// literal `{amount}` placeholder is the backend's, substituted client-side.
  final String? messageBefore;
  final String? messageAfter;
}

/// One coupon from GET /coupons/available — already filtered server-side to
/// ones this customer is currently eligible for (targeting + per-user usage
/// limit), but NOT filtered by current cart total, so it can still fail a
/// [CouponValidationResult] check (e.g. below `minOrderAmount`).
class CouponSummary {
  const CouponSummary({
    required this.id,
    required this.code,
    this.description,
    required this.discountType,
    required this.discountValue,
    this.minOrderAmount = 0,
    this.maxDiscount,
    this.validUntil,
    this.terms,
  });

  final String id;
  final String code;
  final String? description;

  /// 'PERCENTAGE' or 'FLAT'.
  final String discountType;
  final double discountValue;
  final double minOrderAmount;
  final double? maxDiscount;
  final DateTime? validUntil;
  final String? terms;

  /// e.g. "20% off" or "Flat ₹50 off".
  String get discountSummary => discountType == 'PERCENTAGE'
      ? '${discountValue.toStringAsFixed(discountValue.truncateToDouble() == discountValue ? 0 : 1)}% off'
      : 'Flat ₹${discountValue.toStringAsFixed(discountValue.truncateToDouble() == discountValue ? 0 : 1)} off';
}

/// Result of GET /first-time-offers/active — whether THIS customer still
/// qualifies (never placed a prior order) and, if so, which reward tiers
/// are active platform-wide right now. Purely informational: unlike a
/// coupon, there's no code to apply — it auto-applies at checkout.
class FirstTimeOfferResult {
  const FirstTimeOfferResult({required this.eligible, this.tiers = const []});

  final bool eligible;
  final List<CartMilestoneTier> tiers;
}

// ── Request DTOs (no freezed needed for simple request objects) ───────────────

class PlaceOrderRequest {
  const PlaceOrderRequest({
    this.vendorId,
    this.vendorSlotId,
    this.items = const [],
    this.deliveryAddressId,
    this.pickupAddressId,
    this.paymentMethod,
    this.scheduledPickupAt,
    this.notes,
    this.orderDraftId,
    this.draftPaymentMethod,
  });

  /// For draft-based placement, provide [orderDraftId]; for legacy direct
  /// placement provide the fields below.
  final String? orderDraftId;

  /// Payment method for draft-based placement — 'COD' or 'ONLINE'. Separate
  /// from [paymentMethod] (which is legacy-placement only) since the backend
  /// only accepts a plain string here, not the full [PaymentMethod] enum.
  final String? draftPaymentMethod;

  /// Legacy direct placement fields.
  final String? vendorId;
  final String? vendorSlotId;
  final List<OrderItemRequest> items;
  final String? deliveryAddressId;
  final String? pickupAddressId;
  final PaymentMethod? paymentMethod;
  final DateTime? scheduledPickupAt;
  final String? notes;
}

class OrderItemRequest {
  const OrderItemRequest({
    required this.serviceId,
    required this.quantity,
  });
  final String serviceId;
  final int quantity;
}

// ── Invoice / OTP Types ──────────────────────────────────────────────────────

/// Invoice data returned by GET /orders/:id/invoice.
class InvoiceResult {
  const InvoiceResult({
    required this.id,
    required this.orderId,
    required this.invoiceUrl,
    required this.amount,
    required this.gst,
    required this.platformFee,
    required this.total,
    required this.generatedAt,
    this.pdfUrl,
    this.pdfBytes,
    this.fileName,
  });

  final String id;
  final String orderId;
  final String invoiceUrl;
  final double amount;
  final double gst;
  final double platformFee;
  final double total;
  final DateTime generatedAt;
  final String? pdfUrl;
  final Uint8List? pdfBytes;
  final String? fileName;
}

/// OTP data returned by GET /orders/:id/otp.
class OtpResult {
  const OtpResult({
    required this.otp,
    required this.expiresAt,
    required this.type,
    this.isVerified = false,
  });

  /// The 6-digit OTP string.
  final String otp;

  /// Expiry timestamp.
  final DateTime expiresAt;

  /// 'pickup' or 'delivery'.
  final String type;

  /// Whether this OTP has already been verified.
  final bool isVerified;
}

class ReorderResult {
  const ReorderResult({
    required this.success,
    required this.message,
    this.itemCount = 0,
    this.warnings = const [],
  });

  final bool success;
  final String message;
  final int itemCount;
  final List<String> warnings;
}

// ── User Stats Types ─────────────────────────────────────────────────────────

class UserStats {
  const UserStats({
    required this.totalOrders,
    required this.totalSpent,
    this.loyaltyPoints = 0,
  });

  final int totalOrders;
  final double totalSpent;
  final int loyaltyPoints;
}

// ── Review Model ───────────────────────────────────────────────────────────────

class ReviewModel {
  const ReviewModel({
    required this.id,
    required this.userId,
    required this.orderId,
    required this.vendorId,
    required this.vendorRating,
    this.riderRating,
    this.comment,
    required this.createdAt,
    this.updatedAt,
    this.userName,
    this.userAvatarUrl,
  });

  final String id;
  final String userId;
  final String orderId;
  final String vendorId;
  final int vendorRating; // 1–5
  final int? riderRating; // 1–5 (optional)
  final String? comment;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? userName;
  final String? userAvatarUrl;
}

// ── Notification Preferences ───────────────────────────────────────────────────

class NotificationPreferences {
  const NotificationPreferences({
    this.orderUpdates = true,
    this.promotions = false,
    this.newProducts = false,
    this.deliveryUpdates = true,
    this.priceDrops = false,
  });

  final bool orderUpdates;
  final bool promotions;
  final bool newProducts;
  final bool deliveryUpdates;
  final bool priceDrops;
}

class UpdateProfileRequest {
  const UpdateProfileRequest({
    this.name,
    this.email,
    this.avatarUrl,
    this.referralCode,
  });
  final String? name;
  final String? email;
  final String? avatarUrl;

  /// Only ever meaningful on the one-time onboarding "complete your
  /// profile" screen — the backend guards redemption by `referred_by IS
  /// NULL`, so passing this on a later ordinary profile edit is always a
  /// safe no-op regardless.
  final String? referralCode;
}

/// Outcome of a [UpdateProfileRequest.referralCode] redemption attempt —
/// null when no code was submitted at all (the common case for an
/// ordinary profile edit). An unsuccessful redemption is a soft failure:
/// [success] is false but the profile update itself already went through.
class ReferralRedemptionResult {
  const ReferralRedemptionResult({
    required this.success,
    this.redeemed = false,
    this.code,
    this.message,
  });

  final bool success;
  final bool redeemed;
  final String? code;
  final String? message;
}

/// [CustomerRepository.updateProfile]'s full result — the updated user
/// plus, only when a referral code was submitted, its redemption outcome.
class UpdateProfileResult {
  const UpdateProfileResult({required this.user, this.referralOutcome});

  final UserModel user;
  final ReferralRedemptionResult? referralOutcome;
}
