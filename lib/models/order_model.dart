import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:intl/intl.dart';

import '../core/extensions/date_extensions.dart';
import 'order_reconciliation_model.dart';

part 'order_model.freezed.dart';
part 'order_model.g.dart';

// ── Canonical Order Status ────────────────────────────────────────────────────
/// 21-state canonical LNDRY order lifecycle per spec §6.
/// Internal status → customer label mapping is in [OrderStatusX.customerLabel].
enum OrderStatus {
  @JsonValue('PAYMENT_PENDING')
  paymentPending,

  @JsonValue('PAYMENT_FAILED')
  paymentFailed,

  @JsonValue('WAITING_FOR_VENDOR_CONFIRMATION')
  waitingForVendorConfirmation,

  @JsonValue('VENDOR_ACCEPTED')
  vendorAccepted,

  @JsonValue('PICKUP_ASSIGNED')
  pickupAssigned,

  @JsonValue('GOING_FOR_PICKUP')
  goingForPickup,

  @JsonValue('PICKUP_OTP_VERIFIED')
  pickupOtpVerified,

  @JsonValue('PICKED_UP')
  pickedUp,

  @JsonValue('RECEIVED_AT_VENDOR')
  receivedAtVendor,

  @JsonValue('RECONCILIATION_PENDING')
  reconciliationPending,

  @JsonValue('RECONCILIATION_DISPUTED')
  reconciliationDisputed,

  @JsonValue('PROCESSING')
  processing,

  @JsonValue('PACKED')
  packed,

  @JsonValue('DELIVERY_ASSIGNED')
  deliveryAssigned,

  @JsonValue('OUT_FOR_DELIVERY')
  outForDelivery,

  @JsonValue('DELIVERY_OTP_VERIFIED')
  deliveryOtpVerified,

  @JsonValue('DELIVERED')
  delivered,

  @JsonValue('VENDOR_REJECTED')
  vendorRejected,

  @JsonValue('AUTO_REJECTED')
  autoRejected,

  @JsonValue('CUSTOMER_CANCELLED')
  customerCancelled,

  @JsonValue('ADMIN_CANCELLED')
  adminCancelled,

  @JsonValue('REFUND_PENDING')
  refundPending,

  @JsonValue('REFUNDED')
  refunded,
}

extension OrderStatusX on OrderStatus {
  /// Customer-facing label per spec §6 canonical mapping table.
  String get label => switch (this) {
        OrderStatus.paymentPending => 'Payment Pending',
        OrderStatus.paymentFailed => 'Payment Failed',
        OrderStatus.waitingForVendorConfirmation => 'Waiting for Vendor Confirmation',
        OrderStatus.vendorAccepted => 'Scheduled',
        OrderStatus.pickupAssigned => 'Scheduled',
        OrderStatus.goingForPickup => 'Pickup Partner Coming',
        OrderStatus.pickupOtpVerified => 'Picked Up',
        OrderStatus.pickedUp => 'Picked Up',
        OrderStatus.receivedAtVendor => 'At Partner',
        OrderStatus.reconciliationPending => 'Re-evaluation – Waiting for Customer Approval',
        OrderStatus.reconciliationDisputed => 'Disputed — Support Will Call',
        OrderStatus.processing => 'Processing',
        OrderStatus.packed => 'Packed',
        OrderStatus.deliveryAssigned => 'Out for Delivery',
        OrderStatus.outForDelivery => 'Out for Delivery',
        OrderStatus.deliveryOtpVerified => 'Delivered',
        OrderStatus.delivered => 'Delivered',
        OrderStatus.vendorRejected => 'Rejected by Vendor',
        OrderStatus.autoRejected => 'Auto-Rejected',
        OrderStatus.customerCancelled => 'Cancelled',
        OrderStatus.adminCancelled => 'Cancelled',
        OrderStatus.refundPending => 'Refund Pending',
        OrderStatus.refunded => 'Refunded',
      };

  /// Whether this order is still in progress (not a terminal state).
  bool get isActive => switch (this) {
        OrderStatus.delivered ||
        OrderStatus.deliveryOtpVerified ||
        OrderStatus.vendorRejected ||
        OrderStatus.autoRejected ||
        OrderStatus.customerCancelled ||
        OrderStatus.adminCancelled ||
        OrderStatus.refunded =>
          false,
        _ => true,
      };

  /// Whether the customer can cancel at this stage.
  bool get isCancellable => switch (this) {
        OrderStatus.waitingForVendorConfirmation ||
        OrderStatus.vendorAccepted ||
        OrderStatus.pickupAssigned =>
          true,
        _ => false,
      };

  /// Whether the order ended in a rejection that allows selecting another vendor.
  bool get isRejected =>
      this == OrderStatus.vendorRejected || this == OrderStatus.autoRejected;

  /// Whether this is a terminal failure/completion state.
  bool get isTerminal => !isActive;

  /// Whether a refund is applicable or pending.
  bool get hasRefundState =>
      this == OrderStatus.refundPending || this == OrderStatus.refunded;

  /// Pickup OTP should be visible at these statuses (backend visibility=true
  /// is the authoritative source; this is a client-side hint only).
  bool get showPickupOtpHint =>
      this == OrderStatus.goingForPickup || this == OrderStatus.pickupAssigned;

  /// Delivery OTP should be visible at these statuses.
  bool get showDeliveryOtpHint =>
      this == OrderStatus.outForDelivery || this == OrderStatus.deliveryAssigned;
}

// ── Payment Method ─────────────────────────────────────────────────────────────
/// Razorpay-supported payment methods plus Cash on Delivery, which checkout
/// still offers and the backend stores as `payment_method = 'COD'`.
enum PaymentMethod {
  @JsonValue('upi')
  upi,

  @JsonValue('card')
  card,

  @JsonValue('wallet')
  wallet, // Razorpay-supported wallet only; not LNDRY stored-value wallet

  @JsonValue('lndry_wallet')
  lndryWallet, // LNDRY's own stored-value balance — see payments.method 'LNDRY_WALLET' backend-side.

  @JsonValue('cod')
  cod,

  /// A real online payment whose specific gateway sub-method (UPI vs. card
  /// vs. netbanking) isn't known — this is the honest, common case today:
  /// Razorpay only reports the specific sub-method via a webhook, and this
  /// deployment's webhook secret is still a placeholder (see CLAUDE.md), so
  /// it never fires. Showing this instead of guessing "UPI" is deliberate —
  /// a wrong specific label is worse than an accurate general one.
  online,
}

extension PaymentMethodX on PaymentMethod {
  String get label => switch (this) {
        PaymentMethod.upi => 'UPI',
        PaymentMethod.card => 'Card',
        PaymentMethod.wallet => 'Wallet',
        PaymentMethod.lndryWallet => 'LNDRY Wallet',
        PaymentMethod.cod => 'Cash on Delivery',
        PaymentMethod.online => 'Online Payment',
      };
}

// ── Order Payment ──────────────────────────────────────────────────────────────
/// One payment attempt against an order — an order typically has two rows
/// (an ADVANCE at checkout, a BALANCE at/before delivery), which is why a
/// single order-level `paymentMethod`/`isPaid` can't tell the full story:
/// the two legs can genuinely be paid by different methods, and be in
/// different states. See `order.payments` (oldest first) for the real
/// history; the single-value fields remain only for the checkout-time
/// COD-vs-online choice.
enum OrderPaymentPurpose {
  @JsonValue('ADVANCE')
  advance,
  @JsonValue('BALANCE')
  balance,
  // Legacy pre-advance-payment orders paid the whole amount in one go.
  @JsonValue('FULL')
  full,
}

@freezed
class OrderPaymentModel with _$OrderPaymentModel {
  const OrderPaymentModel._();

  const factory OrderPaymentModel({
    required String id,
    required OrderPaymentPurpose purpose,
    PaymentMethod? method,
    required String status,
    required double amount,
    required DateTime createdAt,
  }) = _OrderPaymentModel;

  factory OrderPaymentModel.fromJson(Map<String, dynamic> json) =>
      OrderPaymentModel(
        id: json['id'] as String? ?? '',
        purpose: _parsePaymentPurpose(json['purpose'] as String?),
        method: json['method'] != null
            ? _parsePaymentMethodOrNull(json['method'] as String)
            : null,
        status: json['status'] as String? ?? 'PENDING',
        amount: ((json['amountPaise'] as num?)?.toDouble() ?? 0) / 100.0,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );

  bool get isPaid => status == 'PAID';
}

OrderPaymentPurpose _parsePaymentPurpose(String? raw) => switch (raw) {
      'ADVANCE' => OrderPaymentPurpose.advance,
      'BALANCE' => OrderPaymentPurpose.balance,
      _ => OrderPaymentPurpose.full,
    };

/// Reuses [_normalizePaymentMethod]'s alias handling, then maps onto the
/// enum — never returns null; a genuinely absent method is represented by
/// the nullable [OrderPaymentModel.method] field being left null instead
/// (see its fromJson), not by this function guessing.
PaymentMethod _parsePaymentMethodOrNull(String raw) =>
    switch (_normalizePaymentMethod(raw)) {
      'upi' => PaymentMethod.upi,
      'card' => PaymentMethod.card,
      'wallet' => PaymentMethod.wallet,
      'lndry_wallet' => PaymentMethod.lndryWallet,
      'cod' => PaymentMethod.cod,
      _ => PaymentMethod.online,
    };

// ── Order Item ─────────────────────────────────────────────────────────────────
/// A single service/garment line in an order.
/// NOTE: unitPrice and totalPrice are stored in PAISE (integer) per spec §6.
/// When backend is integrated these will be MoneyPaise = int.
/// For mock phase they remain double to avoid breaking existing mock JSON.
@freezed
class OrderItem with _$OrderItem {
  const factory OrderItem({
    required String serviceId,
    required String serviceName,
    required int quantity,
    @Default(0.0) double unitPrice,
    @Default(0.0) double totalPrice,
    String? notes,
    /// 'kg' / 'sqft' / 'piece' — kg and sqft are continuous-measurement
    /// units whose real decimal quantity, once a rider/vendor correction
    /// has been applied, must be derived as totalPrice/unitPrice rather
    /// than trusted from `quantity` (which becomes a sentinel `1` once
    /// corrected, since order_lines.quantity is an INTEGER column).
    @Default('piece') String unit,
    /// The real order_lines.id this item corresponds to — lets a
    /// reconciliation's per-line problem report (see
    /// ReconciliationProblem.orderLineId) be matched back to the specific
    /// item it's about. Null for legacy orders whose items snapshot
    /// predates order_lines.
    String? orderLineId,
  }) = _OrderItem;

  factory OrderItem.fromJson(Map<String, dynamic> json) =>
      _$OrderItemFromJson(json);
}

// ── Order Model ────────────────────────────────────────────────────────────────
/// Core customer order entity.
/// Money fields are double in mock phase; will become integer paise when
/// ApiCustomerRepository is wired (see spec §6 Money rule).
@freezed
class OrderModel with _$OrderModel {
  const OrderModel._();

  const factory OrderModel({
    required String id,
    @Default('') String orderNumber,
    required String customerId,
    required String vendorId,
    /// The vendor this order was placed with, straight from the order — so
    /// it's shown even when the separate vendor lookup fails or is filtered.
    String? vendorName,
    String? deliveryPartnerId,
    required List<OrderItem> items,
    required OrderStatus status,
    @Default(0.0) double subtotal,
    @Default(0.0) double platformFee,
    @Default(0.0) double gstAmount,
    @Default(0.0) double total,
    @Default(PaymentMethod.online) PaymentMethod paymentMethod,
    @Default(false) bool isPaid,
    /// Server-computed sum of this order's PAID payments, in rupees —
    /// covers the advance and any balance already settled. Used to derive
    /// "balance due" for the delivery-leg payment card without the client
    /// re-deriving it from individual payment rows.
    @Default(0.0) double amountPaid,
    /// Every payment attempt for this order (ADVANCE, BALANCE, oldest
    /// first) — the accurate "how was this actually paid" source. Empty
    /// for an order placed before this field existed; UI should fall back
    /// to the flat [paymentMethod]/[isPaid] summary in that case.
    @Default([]) List<OrderPaymentModel> payments,
    @Default(0.0) double deliveryFee,
    /// Flat/percentage fee configured per-vendor (fee-settings), baked into
    /// `total` but historically never shown as its own line — surfaced here
    /// so the price breakdown always reconciles with the displayed total.
    @Default(0.0) double handlingFee,
    /// The rider's immediate-apply weigh-in correction, if one was ever
    /// recorded — informational only, never requires a customer decision.
    OrderReconciliationModel? riderReevaluation,
    /// The vendor's authoritative recalculation, if one was ever proposed —
    /// requires accept/reject while `status == PENDING_CUSTOMER`, shown
    /// read-only afterwards.
    OrderReconciliationModel? vendorReevaluation,
    @Default('') String pickupAddressId,
    @Default('') String deliveryAddressId,
    DateTime? scheduledPickupAt,
    /// Time-of-day strings (e.g. "16:00:00") for the chosen pickup slot —
    /// null for an express-pickup order, which has no fixed slot. Paired
    /// with [scheduledPickupAt]'s date to show the full pickup window.
    String? pickupSlotStartTime,
    String? pickupSlotEndTime,
    @Default(false) bool isExpressPickup,
    /// 'STANDARD' (the customer chose the services) or 'ASSISTED' ("Book With
    /// Expert Check": the laundry inspects the garments and sets the services
    /// and price through the normal re-evaluation flow).
    @Default('STANDARD') String bookingType,
    DateTime? estimatedDeliveryAt,
    DateTime? pickedUpAt,
    DateTime? deliveredAt,
    String? cancellationReason,
    String? vendorRejectionReason,
    String? customerNotes,
    double? customerRating,
    String? customerReview,
    /// 'MARKETPLACE' for a real app/website order, 'STORE' for an
    /// in-person counter sale at a vendor's own POS (epic-laundry-desktop)
    /// synced here because the buyer's phone matched this account.
    @Default('MARKETPLACE') String source,
    required DateTime createdAt,
    DateTime? updatedAt,
  }) = _OrderModel;

  factory OrderModel.fromJson(Map<String, dynamic> json) =>
      _$OrderModelFromJson(_normalizeOrderJson(json));

  /// A "Book With Expert Check" order. Until the laundry has picked the
  /// services (which turns [items] non-empty once the customer approves),
  /// there is no service price — only the platform/pickup fees exist.
  bool get isAssisted => bookingType == 'ASSISTED';

  /// True while an assisted order is still waiting for the laundry's
  /// inspection — i.e. there is nothing priced to show yet.
  bool get awaitingAssessment => isAssisted && items.isEmpty;

  /// Status wording for display. A walk-in counter order ([source] 'STORE')
  /// reuses a few delivery statuses internally, so it gets its own wording —
  /// otherwise a freshly booked one would read "Scheduled".
  String get statusLabel {
    if (source != 'STORE') return status.label;
    return switch (status) {
      OrderStatus.vendorAccepted => 'Booked',
      OrderStatus.packed => 'Ready',
      _ => status.label,
    };
  }

  /// Human-readable pickup window, e.g. "4:00 PM - 6:00 PM" — null for an
  /// express-pickup order (no fixed slot) or when slot times are
  /// unavailable. [pickupSlotStartTime]/[pickupSlotEndTime] are plain
  /// time-of-day strings ("16:00:00"), not timestamps, so no timezone
  /// conversion applies — the vendor's slot times are already IST.
  String? get pickupSlotLabel {
    if (isExpressPickup) return null;
    final start = pickupSlotStartTime;
    final end = pickupSlotEndTime;
    if (start == null || end == null) return null;
    final startLabel = _formatTimeOfDay(start);
    final endLabel = _formatTimeOfDay(end);
    if (startLabel == null || endLabel == null) return null;
    return '$startLabel - $endLabel';
  }

  /// Full pickup summary for order list/detail screens, e.g.
  /// "Sat, 27 Jun, 4:00 PM - 6:00 PM" for a scheduled slot, or
  /// "Sat, 27 Jun • Express Pickup" for an express order — always in IST
  /// (via [DateTimeExt.toDayDate]), never the raw UTC timestamp.
  String get pickupSummary {
    final date = scheduledPickupAt;
    if (date == null) return 'Scheduled';
    if (isExpressPickup) return '${date.toDayDate} • Express Pickup';
    final slot = pickupSlotLabel;
    return slot == null ? date.toDayDate : '${date.toDayDate}, $slot';
  }
}

/// Formats a "HH:mm:ss" time-of-day string as e.g. "4:00 PM".
String? _formatTimeOfDay(String raw) {
  final parts = raw.split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  return DateFormat('h:mm a').format(DateTime(2000, 1, 1, hour, minute));
}

/// Pre-processes raw JSON before handing it to the generated deserializer.
/// Normalizes status and paymentMethod to prevent crashes on unknown or
/// differently-cased values from mock/backend data.
Map<String, dynamic> _normalizeOrderJson(Map<String, dynamic> json) {
  final normalized = Map<String, dynamic>.from(json);
  if (json['status'] is String) {
    normalized['status'] = _normalizeStatus(json['status'] as String);
  }
  if (json['paymentMethod'] is String) {
    normalized['paymentMethod'] =
        _normalizePaymentMethod(json['paymentMethod'] as String);
  }
  return normalized;
}

/// Normalizes an order status string to match the canonical enum values.
/// Handles case-insensitive matching and provides a safe fallback for
/// unknown or malformed statuses so the UI never crashes on parsing.
String _normalizeStatus(String raw) {
  final upper = raw.toUpperCase().trim();
  // Map of known aliases for backwards compatibility.
  const aliases = <String, String>{
    'CONFIRMED': 'VENDOR_ACCEPTED',
  };
  // Canonical status strings from _$OrderStatusEnumMap.
  const validStatuses = <String>[
    'PAYMENT_PENDING',
    'PAYMENT_FAILED',
    'WAITING_FOR_VENDOR_CONFIRMATION',
    'VENDOR_ACCEPTED',
    'PICKUP_ASSIGNED',
    'GOING_FOR_PICKUP',
    'PICKUP_OTP_VERIFIED',
    'PICKED_UP',
    'RECEIVED_AT_VENDOR',
    'RECONCILIATION_PENDING',
    'RECONCILIATION_DISPUTED',
    'PROCESSING',
    'PACKED',
    'DELIVERY_ASSIGNED',
    'OUT_FOR_DELIVERY',
    'DELIVERY_OTP_VERIFIED',
    'DELIVERED',
    'VENDOR_REJECTED',
    'AUTO_REJECTED',
    'CUSTOMER_CANCELLED',
    'ADMIN_CANCELLED',
    'REFUND_PENDING',
    'REFUNDED',
  ];

  // Check aliases first.
  if (aliases.containsKey(upper)) return aliases[upper]!;
  // Check direct match (case-insensitive).
  for (final v in validStatuses) {
    if (v == upper) return v;
  }
  // Safe fallback — unknown status defaults to PAYMENT_PENDING.
  return 'PAYMENT_PENDING';
}

/// Normalizes a payment method string to match the canonical enum values.
/// Handles case-insensitive matching and provides a safe fallback.
String _normalizePaymentMethod(String raw) {
  final upper = raw.toUpperCase().trim();
  // Map of known aliases/legacy values. NET_BANKING used to fall through to
  // 'upi' — a specific, actively wrong label (this order was never paid via
  // UPI) — 'online' is honest about what's actually known.
  const aliases = <String, String>{
    'CASH': 'cod',
    'COD': 'cod',
    'CREDIT_CARD': 'card',
    'DEBIT_CARD': 'card',
    'NET_BANKING': 'online',
    'ONLINE': 'online',
  };
  // Canonical payment method strings.
  const validMethods = <String>[
    'upi',
    'card',
    'wallet',
    'lndry_wallet',
    'cod',
    'online',
  ];

  // Check aliases first (case-insensitive).
  if (aliases.containsKey(upper)) return aliases[upper]!;
  // Check direct match (case-insensitive).
  for (final v in validMethods) {
    if (v.toUpperCase() == upper) return v;
  }
  // Safe fallback — 'online' rather than a specific gateway method:
  // orders.payment_method is frequently just the literal string 'ONLINE'
  // (the checkout-time COD-vs-online choice, not a real gateway method —
  // see placeOrderFromDraft backend-side), which used to silently default
  // to displaying "UPI" regardless of how the order was actually paid.
  return 'online';
}
