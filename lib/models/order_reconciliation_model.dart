import 'package:freezed_annotation/freezed_annotation.dart';

part 'order_reconciliation_model.freezed.dart';
part 'order_reconciliation_model.g.dart';

/// Postgres NUMERIC columns (e.g. `weight_kg`) come back from node-pg as
/// strings, not numbers, to avoid precision loss — unlike INTEGER paise
/// columns, which arrive as plain JS numbers.
double? _numericToDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

num _numToNum(dynamic value) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '') ?? 0;
}

/// A single garment line's before/after correction within a reconciliation
/// proposal — mirrors the backend's `order-recalculation.js` lineChanges shape.
@freezed
class ReconciliationLineChange with _$ReconciliationLineChange {
  const factory ReconciliationLineChange({
    /// Null for a brand-new line (see [isNew]) — it doesn't exist in
    /// order_lines yet, only gets INSERTed once the customer accepts.
    @JsonKey(name: 'order_line_id') String? orderLineId,
    @JsonKey(name: 'previous_garment_type_id') String? previousGarmentTypeId,
    @JsonKey(name: 'proposed_garment_type_id') String? proposedGarmentTypeId,
    @JsonKey(name: 'previous_name') String? previousName,
    @JsonKey(name: 'proposed_name') String? proposedName,
    @JsonKey(name: 'previous_unit') String? previousUnit,
    @JsonKey(name: 'proposed_unit') String? proposedUnit,
    @JsonKey(name: 'previous_rate_paise') @Default(0) int previousRatePaise,
    @JsonKey(name: 'proposed_rate_paise') @Default(0) int proposedRatePaise,
    @JsonKey(name: 'previous_quantity', fromJson: _numToNum) @Default(0) num previousQuantity,
    @JsonKey(name: 'proposed_quantity', fromJson: _numToNum) @Default(0) num proposedQuantity,
    @JsonKey(name: 'previous_total_paise') @Default(0) int previousTotalPaise,
    @JsonKey(name: 'proposed_total_paise') @Default(0) int proposedTotalPaise,
    @JsonKey(name: 'is_weight_adjustment') @Default(false) bool isWeightAdjustment,
    @JsonKey(name: 'is_reclassified') @Default(false) bool isReclassified,
    /// A service that wasn't on the order at all — a genuine addition, or
    /// the destination for a partial quantity moved out of an existing
    /// continuous-unit line.
    @JsonKey(name: 'is_new') @Default(false) bool isNew,
  }) = _ReconciliationLineChange;

  factory ReconciliationLineChange.fromJson(Map<String, dynamic> json) =>
      _$ReconciliationLineChangeFromJson(json);
}

/// A vendor's proposed recalculation currently (or previously) awaiting this
/// customer's accept/reject decision — `GET /orders/:id/reconciliation`.
@freezed
class OrderReconciliationModel with _$OrderReconciliationModel {
  const factory OrderReconciliationModel({
    required String id,
    @JsonKey(name: 'order_id') required String orderId,
    /// 'RIDER_PICKUP' or 'VENDOR_RECEIPT' — only VENDOR_RECEIPT proposals
    /// ever reach the customer for a decision.
    required String stage,
    /// 'PENDING_CUSTOMER' | 'ACCEPTED' | 'REJECTED' | 'APPLIED'.
    required String status,
    @JsonKey(name: 'previous_subtotal_paise') @Default(0) int previousSubtotalPaise,
    @JsonKey(name: 'proposed_subtotal_paise') @Default(0) int proposedSubtotalPaise,
    @JsonKey(name: 'previous_payable_amount_paise') @Default(0) int previousPayableAmountPaise,
    @JsonKey(name: 'proposed_payable_amount_paise') @Default(0) int proposedPayableAmountPaise,
    @JsonKey(name: 'previous_weight_kg', fromJson: _numericToDouble) double? previousWeightKg,
    @JsonKey(name: 'proposed_weight_kg', fromJson: _numericToDouble) double? proposedWeightKg,
    @JsonKey(name: 'line_changes') @Default([]) List<ReconciliationLineChange> lineChanges,
    String? reason,
    @Default([]) List<String> photos,
    /// e.g. 'VENDOR_RIDER', 'VENDOR_OWNER', 'VENDOR_STAFF' — who performed
    /// this re-evaluation.
    @JsonKey(name: 'proposed_by_role') String? proposedByRole,
    @JsonKey(name: 'created_at') DateTime? createdAt,
  }) = _OrderReconciliationModel;

  factory OrderReconciliationModel.fromJson(Map<String, dynamic> json) =>
      _$OrderReconciliationModelFromJson(json);
}
