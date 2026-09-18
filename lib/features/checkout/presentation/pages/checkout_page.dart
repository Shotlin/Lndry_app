import 'dart:async';

import '../../../../config/env.dart';
import '../../../../core/constants/asset_constants.dart';
import '../../../../core/design/design_system.dart';
import '../../../../core/extensions/extensions.dart';
import '../../../../core/network/network.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../models/models.dart';
import '../../../../repositories/repositories.dart';
import '../../../cart/presentation/providers/cart_providers.dart';
import '../../../offers/presentation/providers/offers_providers.dart';
import '../widgets/checkout_brand_header.dart';

/// Checkout selections passed to the payment screen via GoRouter extra.
class CheckoutSession {
  const CheckoutSession({
    required this.deliveryAddressId,
    required this.pickupAddressId,
    required this.finalPrice,
    this.selectedSlot,
    this.isExpressPickup = false,
    this.pickupDateIdx = 0,
    this.orderDraftId,
    this.backendSubtotal,
    this.backendDeliveryFee,
    this.backendTaxes,
    this.backendDiscount,
    this.backendTotal,
  });

  final String deliveryAddressId;
  final String pickupAddressId;
  final double finalPrice;
  final String? selectedSlot;
  final bool isExpressPickup;
  final int pickupDateIdx;

  /// Order draft ID from POST /orders/prepare (API mode).
  final String? orderDraftId;

  /// Backend-computed price breakdown (only in API mode).
  final double? backendSubtotal;
  final double? backendDeliveryFee;
  final double? backendTaxes;
  final double? backendDiscount;
  final double? backendTotal;
}

/// How the customer wants their pickup timed — the single source of truth
/// for the non-express pickup choice. Express pickup is a separate,
/// orthogonal flag (`_isExpressPickup`): when it's on, this mode is not
/// consulted at all; when it's off, exactly one of these two applies.
///
/// [anytime] hands the choice to the backend — the earliest capacity within
/// whichever 12-hour service window (8 AM–8 PM or 8 PM–8 AM) is currently
/// running gets auto-assigned. The customer-facing label is always
/// "Anytime" — the window is shown only as secondary detail, never as a
/// replacement for that label.
/// [schedule] is the manual date + slot flow, backed by the real
/// `getPickupSlots` API.
enum _PickupTimeMode { anytime, schedule }

class CheckoutPage extends ConsumerStatefulWidget {
  const CheckoutPage({super.key});

  @override
  ConsumerState<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends ConsumerState<CheckoutPage> {
  bool _isLoading = true;
  AddressModel? _selectedAddress;
  List<AddressModel> _addresses = [];

  // Date select state: 0 = Today, 1 = Tomorrow
  int _selectedDateIdx = 0;

  // Anytime vs Schedule — see `_PickupTimeMode` above. Only consulted when
  // `_isExpressPickup` is false; the two flags are never contradictory
  // because the UI that would set `_pickupTimeMode` is not shown at all
  // while express pickup is selected.
  _PickupTimeMode _pickupTimeMode = _PickupTimeMode.anytime;

  // Selected non-express slot id (schedule) or auto-assigned slot id
  // (anytime). Null means "not yet resolved".
  String? _selectedSlot;
  bool _isExpressPickup = false;

  // ── Backend-computed prices (from POST /orders/prepare) ───────────────────
  bool _backendPricesLoaded = false;
  bool _isPreparingCheckout = false;
  // Bill breakdown starts collapsed — the sticky bar leads with one clean
  // "Total Payable" figure (Zomato/Blinkit-style), and the itemized charges
  // only show when the customer taps to expand it.
  bool _showBillDetails = false;
  double _backendSubtotal = 0;
  double _backendDeliveryFee = 0;
  double _backendTaxes = 0;
  double _backendExpressFee = 0;
  double _backendDiscount = 0;
  String? _backendDiscountReason;
  double _backendTotal = 0;
  List<_ChargeLine> _backendExtraCharges = const [];
  String? _orderDraftId;
  List<PickupSlot> _pickupSlots = const [];
  bool _isLoadingSlots = false;
  bool _slotsLoadFailed = false;
  bool _isApiMode = false;

  final List<String> _slots = [
    '09:00 AM - 10:00 AM',
    '10:00 AM - 11:00 AM',
    '11:00 AM - 12:00 PM',
    '02:00 PM - 03:00 PM',
    '03:00 PM - 04:00 PM',
    '04:00 PM - 05:00 PM',
  ];

  @override
  void initState() {
    super.initState();
    _isApiMode = !Env.useMocksForVisualTestsOnly;
    _loadCheckoutData();
    _maybeApplyPendingCoupon();
  }

  /// Picks up a coupon the customer applied from the Coupons & Offers page
  /// (see `pendingCouponCodeProvider`'s doc comment) — prefills and
  /// re-validates it here so it's ready the moment checkout loads, instead
  /// of the customer having to type the code again.
  Future<void> _maybeApplyPendingCoupon() async {
    final pending = ref.read(pendingCouponCodeProvider);
    if (pending == null || pending.isEmpty) return;
    ref.read(pendingCouponCodeProvider.notifier).state = null;
    _couponController.text = pending;
    _couponExpanded = true;
    await _onApplyCoupon();
  }

  void _loadCheckoutData() async {
    setState(() => _isLoading = true);
    final repo = ref.read(customerRepositoryProvider);
    try {
      final list = await repo.getAddresses();
      if (mounted) {
        setState(() {
          _addresses = list;
          _selectedAddress = list.firstWhere(
            (a) => a.isDefault,
            orElse: () => list.isNotEmpty
                ? list.first
                : const AddressModel(
                    id: '',
                    userId: '',
                    line1: '',
                    city: '',
                    state: '',
                    pincode: '',
                    type: AddressType.home),
          );
          _selectedSlot = _isApiMode ? null : _slots.first;
          _isLoading = false;
        });
        if (_isApiMode) {
          unawaited(_loadPickupSlots());
        } else {
          unawaited(_loadBackendPrices());
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onAddNewAddress() async {
    // AppBottomSheet.show uses useRootNavigator: true; must pop the same
    // navigator explicitly (see order_revision_sheet.dart) — otherwise
    // this no-ops (or pops the wrong thing) and the sheet never closes.
    Navigator.of(context, rootNavigator: true).pop();
    final result = await context.push<AddressModel>(AppRoutes.mapAddress);
    if (result != null && mounted) {
      _loadCheckoutData();
    }
  }

  void _showAddressModal() {
    AppBottomSheet.show<void>(
      context: context,
      title: 'Select Delivery Address',
      primaryActionLabel: 'Confirm Address',
      secondaryActionLabel: '+ Add New Address',
      onSecondaryAction: _onAddNewAddress,
      child: StatefulBuilder(
        builder: (context, setModalState) => ListView.separated(
          shrinkWrap: true,
          itemCount: _addresses.length,
          separatorBuilder: (_, __) => const Gap(8),
          itemBuilder: (context, idx) {
            final addr = _addresses[idx];
            final isChosen = _selectedAddress?.id == addr.id;

            return AppCard.outlined(
              borderColor: isChosen ? AppColors.primary : AppColors.outline,
              backgroundColor:
                  isChosen ? AppColors.primaryContainer : AppColors.transparent,
              onTap: () {
                setModalState(() => _selectedAddress = addr);
                setState(() => _selectedAddress = addr);
              },
              child: Row(
                children: [
                  Icon(
                    addr.type == AddressType.home
                        ? AppIcons.homeOutlined
                        : AppIcons.store,
                    color:
                        isChosen ? AppColors.primary : AppColors.textSecondary,
                  ),
                  Gap(AppSpacing.cardGap.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(addr.type.label,
                            style: AppTypography.labelLarge
                                .copyWith(fontWeight: FontWeight.bold)),
                        Text(
                          '${addr.line1}, ${addr.city}',
                          style: AppTypography.bodySmall
                              .copyWith(color: AppColors.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (isChosen)
                    Icon(AppIcons.success,
                        color: AppColors.primary, size: 18.r),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _checkoutDate() {
    final date = DateTime.now().add(Duration(days: _selectedDateIdx));
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  /// The currently-running 12-hour service window — 8:00 AM–8:00 PM during
  /// the day, 8:00 PM–8:00 AM overnight. This is SECONDARY detail only —
  /// "Anytime" itself is always the primary label the customer sees; this
  /// window is what "Anytime" resolves to behind the scenes.
  ({String rangeLabel, String shortLabel, bool isDayWindow}) _anytimeWindow() {
    final hour = DateTime.now().hour;
    final isDayWindow = hour >= 8 && hour < 20;
    final start = AppDateUtils.formatTimeOfDay(isDayWindow ? '08:00' : '20:00');
    final end = AppDateUtils.formatTimeOfDay(isDayWindow ? '20:00' : '08:00');
    return (
      rangeLabel: '$start – $end ${isDayWindow ? 'today' : 'tonight'}',
      shortLabel: '$start – $end',
      isDayWindow: isDayWindow,
    );
  }

  /// Picks the earliest real, available slot inside the current 12-hour
  /// window for "Anytime" pickup — falling back to the overall earliest slot
  /// if nothing lands inside the window — instead of requiring the customer
  /// to pick one themselves.
  String? _pickBestSlotForAnytime(List<PickupSlot> slots) {
    if (slots.isEmpty) return null;
    final window = _anytimeWindow();
    bool inWindow(PickupSlot s) {
      final h = int.tryParse(s.startTime.split(':').first);
      if (h == null) return false;
      return window.isDayWindow ? (h >= 8 && h < 20) : (h >= 20 || h < 8);
    }

    final windowed = slots.where(inWindow).toList();
    final pool = windowed.isNotEmpty ? windowed : slots;
    final sorted = [...pool]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    return sorted.first.id;
  }

  void _setPickupTimeMode(_PickupTimeMode mode) {
    if (_pickupTimeMode == mode) return;
    setState(() {
      _pickupTimeMode = mode;
      _backendPricesLoaded = false;
      _orderDraftId = null;
      // Anytime always refers to the window running right now, so pull the
      // date selector back to Today if the customer had Tomorrow queued up
      // under Schedule.
      if (mode == _PickupTimeMode.anytime) {
        _selectedDateIdx = 0;
      }
    });
    if (_isApiMode) {
      unawaited(_loadPickupSlots());
    } else {
      unawaited(_loadBackendPrices());
    }
  }

  Future<void> _loadPickupSlots() async {
    if (!_isApiMode) return;

    final vendorId = _cartVendorId(ref.read(cartStateProvider));
    if (vendorId == null) {
      if (mounted) {
        setState(() {
          _pickupSlots = const [];
          _selectedSlot = null;
        });
      }
      return;
    }

    setState(() {
      _isLoadingSlots = true;
      _slotsLoadFailed = false;
      _backendPricesLoaded = false;
      _orderDraftId = null;
    });

    try {
      final slots = await ref.read(customerRepositoryProvider).getPickupSlots(
            vendorId: vendorId,
            date: _checkoutDate(),
          );
      if (!mounted) return;
      final activeSlots = slots
          .where((slot) => slot.isActive && slot.remainingCapacity > 0)
          .toList();
      setState(() {
        _pickupSlots = activeSlots;
        if (activeSlots.isEmpty) {
          _selectedSlot = null;
        } else if (_pickupTimeMode == _PickupTimeMode.anytime) {
          _selectedSlot = _pickBestSlotForAnytime(activeSlots);
        } else {
          final currentStillAvailable =
              activeSlots.any((slot) => slot.id == _selectedSlot);
          _selectedSlot =
              currentStillAvailable ? _selectedSlot : activeSlots.first.id;
        }
        _isLoadingSlots = false;
      });
      if (_selectedAddress != null && _selectedSlot != null) {
        unawaited(
          _refreshBackendQuote(ref.read(cartStateProvider), silent: true),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pickupSlots = const [];
        _selectedSlot = null;
        _isLoadingSlots = false;
        _slotsLoadFailed = true;
      });
    }
  }

  /// Fetch backend-computed prices from POST /orders/prepare.
  Future<void> _loadBackendPrices() async {
    if (_isApiMode) {
      setState(() => _backendPricesLoaded = false);
      return;
    }

    final repo = ref.read(customerRepositoryProvider);
    try {
      final draft = await repo.prepareOrder(
        quoteId: 'quote_mock',
        addressId: _selectedAddress?.id ?? 'addr_1',
        slotId: 'slot_mock',
      );
      if (mounted) {
        setState(() {
          if (draft.orderDraftId.isNotEmpty) {
            _orderDraftId = draft.orderDraftId;
            _backendTotal = draft.payableAmountPaise / 100.0;
            _backendSubtotal =
                ((draft.snapshot?['subtotal'] as num?)?.toDouble() ?? 0) /
                    100.0;
            _backendDeliveryFee =
                ((draft.snapshot?['delivery_fee'] as num?)?.toDouble() ?? 0) /
                    100.0;
            _backendTaxes =
                ((draft.snapshot?['tax'] as num?)?.toDouble() ?? 0) / 100.0;
            _backendPricesLoaded = true;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _backendPricesLoaded = false);
    }
  }

  /// Fetches the real backend-computed quote (creates a quote, holds the
  /// selected slot, and prepares an order draft) and stores the amounts in
  /// `_backendXxx` state — but does not navigate anywhere. Split out of
  /// `_prepareApiCheckout` so the price breakdown can be refreshed as soon
  /// as address+slot are known, instead of staying hidden behind an
  /// "Estimated Total" placeholder until the user taps "Proceed to Payment".
  /// [silent] suppresses error snackbars for background/proactive refreshes
  /// (e.g. right after slots load) where the user hasn't asked to pay yet.
  Future<bool> _refreshBackendQuote(CartState cart,
      {bool silent = false}) async {
    final address = _selectedAddress;
    final slotId = _selectedSlot;
    if (address == null || address.id.isEmpty) {
      if (!silent) {
        AppSnackBar.showError(context, 'Please select a validated address.');
      }
      return false;
    }
    if (!_isExpressPickup && (slotId == null || slotId.isEmpty)) {
      if (!silent) {
        AppSnackBar.showError(
          context,
          _pickupTimeMode == _PickupTimeMode.anytime
              ? 'No pickup slots are available right now. Please try Schedule instead.'
              : 'Please select an available pickup slot.',
        );
      }
      return false;
    }

    final quoteInput = _buildQuoteInput(cart);
    if (quoteInput == null) {
      if (!silent) {
        AppSnackBar.showError(
          context,
          'Live quote cannot be created for this cart. Please select one service category from one vendor.',
        );
      }
      return false;
    }

    try {
      final repo = ref.read(customerRepositoryProvider);
      final quote = await repo.createQuote(
        vendorId: quoteInput.vendorId,
        vendorServiceId: quoteInput.vendorServiceId,
        garmentLines: quoteInput.lines,
      );
      if (quote.quoteId.isEmpty) {
        throw const FormatException('Quote creation failed.');
      }

      // Express pickup bypasses the vendor_slots capacity system entirely —
      // no slot to hold.
      if (!_isExpressPickup) {
        final hold = await repo.holdSlot(
          vendorId: quoteInput.vendorId,
          slotId: slotId!,
          date: _checkoutDate(),
          quoteId: quote.quoteId,
        );
        if (hold.holdId.isEmpty) {
          throw const FormatException('Pickup slot hold failed.');
        }
      }

      final draft = await repo.prepareOrder(
        quoteId: quote.quoteId,
        addressId: address.id,
        slotId: _isExpressPickup ? null : slotId,
        isExpressPickup: _isExpressPickup,
        couponCode:
            _couponApplied ? _couponController.text.trim().toUpperCase() : null,
      );
      if (draft.orderDraftId.isEmpty || draft.payableAmountPaise <= 0) {
        throw const FormatException('Order draft is unavailable.');
      }

      final amounts = _CheckoutAmounts.fromDraft(draft);
      if (!mounted) return false;
      setState(() {
        _orderDraftId = draft.orderDraftId;
        _backendSubtotal = amounts.subtotal;
        _backendDeliveryFee = amounts.deliveryFee;
        _backendTaxes = amounts.taxes;
        _backendExpressFee = amounts.expressFee;
        _backendDiscount = amounts.discount;
        _backendDiscountReason = amounts.discountReason;
        _backendTotal = amounts.total;
        _backendExtraCharges = amounts.extraCharges;
        _backendPricesLoaded = true;
      });
      return true;
    } on ApiException catch (e) {
      if (!mounted) return false;
      if (e.code == 'INVALID_COUPON') {
        setState(() => _couponApplied = false);
      }
      if (!silent) {
        AppSnackBar.showError(context, e.message);
      }
      return false;
    } catch (e) {
      if (!mounted) return false;
      if (!silent) {
        AppSnackBar.showError(
          context,
          'Live checkout could not be prepared. Please retry.',
        );
      }
      return false;
    }
  }

  Future<void> _prepareApiCheckout(CartState cart) async {
    if (_isPreparingCheckout) return;
    setState(() => _isPreparingCheckout = true);

    final success = await _refreshBackendQuote(cart);

    if (!mounted) return;
    setState(() => _isPreparingCheckout = false);

    if (success) {
      _goToPayment(
        finalPrice: _backendTotal,
        backendSubtotal: _backendSubtotal,
        backendDeliveryFee: _backendDeliveryFee,
        backendTaxes: _backendTaxes,
        backendDiscount: _backendDiscount,
        backendTotal: _backendTotal,
        orderDraftId: _orderDraftId,
      );
    }
  }

  /// A single cart may span more than one of the vendor's services (e.g. a
  /// per-kg wash line and a per-piece dry-clean line) — the backend
  /// resolves each line's rate independently against (vendor_id,
  /// garment_type_id), so only a single vendor is required here, not a
  /// single service. `vendorServiceId` is kept only as an informational
  /// field on the quote request, set when every line happens to share one.
  _QuoteInput? _buildQuoteInput(CartState cart) {
    if (cart.cart.items.isEmpty || cart.services.isEmpty) return null;

    String? vendorId;
    String? vendorServiceId;
    var singleService = true;
    final lines = <QuoteGarmentLine>[];

    for (final item in cart.cart.items) {
      final service = cart.services.firstWhere(
        (svc) => svc.id == item.serviceId,
        orElse: () => const ServiceModel(
          id: '',
          vendorId: '',
          name: '',
          description: '',
          category: ServiceCategory.wash,
          minWeightKg: 0,
        ),
      );
      if (service.id.isEmpty || item.quantity <= 0) return null;

      final serviceVendorId = service.vendorId;
      final backendVendorServiceId =
          _tagValue(service.tags, 'vendor_service_id') ?? service.id;
      final garmentTypeId =
          _tagValue(service.tags, 'garment_type_id') ?? service.id;

      vendorId ??= serviceVendorId;
      vendorServiceId ??= backendVendorServiceId;
      if (vendorId != serviceVendorId || garmentTypeId.isEmpty) {
        return null;
      }
      if (vendorServiceId != backendVendorServiceId) {
        singleService = false;
      }

      lines.add(QuoteGarmentLine(
        garmentTypeId: garmentTypeId,
        quantity: item.quantity,
      ));
    }

    if (vendorId == null || lines.isEmpty) {
      return null;
    }
    return _QuoteInput(
      vendorId: vendorId,
      vendorServiceId: singleService ? vendorServiceId : null,
      lines: lines,
    );
  }

  String? _cartVendorId(CartState cart) {
    final vendorIds = cart.cart.items
        .map((item) => item.vendorId)
        .where((id) => id.isNotEmpty)
        .toSet();
    return vendorIds.length == 1 ? vendorIds.first : null;
  }

  String? _tagValue(List<String> tags, String key) {
    final prefix = '$key:';
    for (final tag in tags) {
      if (tag.startsWith(prefix)) return tag.substring(prefix.length);
    }
    return null;
  }

  Future<void> _onProceedToPayment(CartState cart) async {
    if (_selectedAddress == null || _selectedAddress!.id.isEmpty) {
      AppSnackBar.showError(context, 'Please select a delivery address.');
      return;
    }

    // Flat/house number missing — this is folded into `line1`, so an empty
    // line1 means the address was never actually completed. Block checkout
    // and send the user to fill it in (map skipped, since coordinates are
    // already known) rather than letting an order place against an address
    // a rider can't actually find.
    if (_selectedAddress!.line1.trim().isEmpty) {
      AppSnackBar.showError(
        context,
        'Please add your flat / house number to continue.',
      );
      final updated = await context.push<AddressModel>(
        AppRoutes.mapAddress,
        extra: (
          existingAddress: _selectedAddress,
          isEditingExisting: false,
          requireFlatNumber: true,
          prefilledLocation: null,
        ),
      );
      if (updated != null && mounted) {
        setState(() {
          _selectedAddress = updated;
          _addresses = [
            for (final a in _addresses) a.id == updated.id ? updated : a,
          ];
        });
      }
      return;
    }

    if (_selectedSlot == null && !_isExpressPickup) {
      AppSnackBar.showError(
        context,
        _pickupTimeMode == _PickupTimeMode.anytime
            ? 'No pickup slots are available right now. Please try Schedule instead.'
            : 'Please select a pickup time slot.',
      );
      return;
    }

    if (_isApiMode) {
      await _prepareApiCheckout(cart);
      return;
    }

    final price = _backendPricesLoaded
        ? _backendTotal
        : cart.total + (_isExpressPickup ? 99.0 : 0.0);

    final String? orderDraftId = _backendPricesLoaded ? _orderDraftId : null;
    final double? backendSubtotal =
        _backendPricesLoaded ? _backendSubtotal : null;
    final double? backendDeliveryFee =
        _backendPricesLoaded ? _backendDeliveryFee : null;
    final double? backendTaxes = _backendPricesLoaded ? _backendTaxes : null;
    final double? backendTotal = _backendPricesLoaded ? _backendTotal : null;

    _goToPayment(
      finalPrice: price,
      backendSubtotal: backendSubtotal,
      backendDeliveryFee: backendDeliveryFee,
      backendTaxes: backendTaxes,
      backendDiscount: _backendPricesLoaded ? _backendDiscount : null,
      backendTotal: backendTotal,
      orderDraftId: orderDraftId,
    );
  }

  void _goToPayment({
    required double finalPrice,
    required double? backendSubtotal,
    required double? backendDeliveryFee,
    required double? backendTaxes,
    required double? backendDiscount,
    required double? backendTotal,
    required String? orderDraftId,
  }) {
    if (!context.mounted) return;
    context.push(
      AppRoutes.payment,
      extra: CheckoutSession(
        deliveryAddressId: _selectedAddress!.id,
        pickupAddressId: _selectedAddress!.id,
        finalPrice: finalPrice,
        selectedSlot: _selectedSlotLabel(),
        isExpressPickup: _isExpressPickup,
        pickupDateIdx: _selectedDateIdx,
        orderDraftId: orderDraftId,
        backendSubtotal: backendSubtotal,
        backendDeliveryFee: backendDeliveryFee,
        backendTaxes: backendTaxes,
        backendDiscount: backendDiscount,
        backendTotal: backendTotal,
      ),
    );
  }

  String? _selectedSlotLabel() {
    if (_isExpressPickup) return 'Express (within 60 min)';
    if (_pickupTimeMode == _PickupTimeMode.anytime) {
      return 'Anytime (${_anytimeWindow().shortLabel})';
    }
    if (_isApiMode) {
      final slot = _pickupSlots.where((slot) => slot.id == _selectedSlot);
      if (slot.isEmpty) return null;
      final selected = slot.first;
      return selected.label ?? '${selected.startTime} - ${selected.endTime}';
    }
    return _selectedSlot;
  }

  /// The slot the customer picked under Schedule mode, formatted for the
  /// compact "Pickup scheduled" confirmation strip.
  String? _scheduledSlotSummary() {
    if (_pickupTimeMode != _PickupTimeMode.schedule || _selectedSlot == null) {
      return null;
    }
    final dateLabel = _selectedDateIdx == 0 ? 'Today' : 'Tomorrow';
    if (_isApiMode) {
      final match = _pickupSlots.where((s) => s.id == _selectedSlot);
      if (match.isEmpty) return null;
      final slot = match.first;
      final timeLabel = slot.label ??
          AppDateUtils.formatTimeRange(slot.startTime, slot.endTime);
      return '$dateLabel, $timeLabel';
    }
    return '$dateLabel, $_selectedSlot';
  }

  // ── Coupon state ───────────────────────────────────────────────────────────

  final _couponController = TextEditingController();
  final _couponFocusNode = FocusNode();
  bool _couponApplied = false;
  bool _couponFocused = false;
  bool _isCouponValidating = false;
  bool _couponExpanded = false;

  // ── Notes state ────────────────────────────────────────────────────────────
  final _notesController = TextEditingController();
  bool _notesExpanded = false;
  static const int _notesMaxLength = 200;

  @override
  void dispose() {
    _couponController.dispose();
    _couponFocusNode.dispose();
    _notesController.dispose();
    super.dispose();
  }

  /// Recomputes `_backendTotal` instantly from the already-known fee
  /// components whenever the coupon discount changes. `_backendTotal` is a
  /// separately-cached field (see `_stickyBottomBar`'s "Total Payable") that
  /// only `_refreshBackendQuote`/`_loadBackendPrices` otherwise update — so
  /// without this, applying or removing a coupon left the headline total
  /// frozen at its pre-change value while the itemized breakdown below it
  /// updated immediately, visibly disagreeing with each other. This gives
  /// zero-latency optimistic feedback; the background `_refreshBackendQuote`
  /// call kicked off right after still reconciles with the authoritative,
  /// backend-confirmed figure (e.g. re-applying the first-order free-delivery
  /// offer once no coupon is active).
  double _localTotalWithDiscount(double discount) {
    final extras =
        _backendExtraCharges.fold<double>(0, (sum, line) => sum + line.amount);
    final total = _backendSubtotal +
        _backendDeliveryFee +
        _backendTaxes +
        _backendExpressFee +
        extras -
        discount;
    return total < 0 ? 0 : total;
  }

  /// Validates the entered coupon against the current cart subtotal for
  /// instant feedback. This does NOT replace the authoritative validation
  /// that happens server-side inside `prepareOrder(...)` at actual submission
  /// time (see `_prepareApiCheckout`) — it just applies/reflects the coupon
  /// immediately so the user isn't left guessing after tapping "Apply". A
  /// silent `_refreshBackendQuote` right after reconciles `_backendTotal`
  /// (and rolls the whole thing back via its own `INVALID_COUPON` handling
  /// if the backend ultimately disagrees).
  Future<void> _onApplyCoupon() async {
    final code = _couponController.text.trim();
    if (code.isEmpty || _isCouponValidating) return;

    setState(() => _isCouponValidating = true);

    try {
      final repo = ref.read(customerRepositoryProvider);
      final cartState = ref.read(cartStateProvider);
      final result = await repo.validateCoupon(
        code: code,
        cartTotal: cartState.subtotal,
      );
      if (!mounted) return;

      if (result.valid) {
        setState(() {
          _couponApplied = true;
          _backendDiscount = result.discount;
          _backendDiscountReason =
              result.discount > 0 ? 'Coupon "$code" applied' : null;
          if (_backendPricesLoaded) {
            _backendTotal = _localTotalWithDiscount(result.discount);
          }
          _isCouponValidating = false;
        });
        AppSnackBar.showSuccess(context, result.message ?? 'Coupon applied!');
        if (_isApiMode) {
          unawaited(_refreshBackendQuote(cartState, silent: true));
        }
      } else {
        setState(() => _isCouponValidating = false);
        AppSnackBar.showError(
          context,
          result.message ?? 'This coupon code is not valid.',
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isCouponValidating = false);
      AppSnackBar.showError(context, e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isCouponValidating = false);
      AppSnackBar.showError(
        context,
        'Could not validate coupon. Please try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // This page always renders the light/premium design from the approved
    // reference (white background, soft shadows) regardless of the device's
    // system theme — reading the real system brightness here previously
    // caused cards to pick dark-theme colors (grayish fills, dim borders)
    // while the Scaffold stayed forced white, producing a mismatched,
    // "cheap" look on any phone with system dark mode on.
    const isDark = false;
    final cartState = ref.watch(cartStateProvider);

    // `_maybeApplyPendingCoupon` in `initState` only covers a coupon that was
    // already pending the moment this page was first built (e.g. applied
    // from Profile's Offers page, reached separately from Checkout). It
    // can't fire again for a coupon applied from Checkout's own "View all"
    // link, since popping back from Offers returns to this SAME CheckoutPage
    // instance rather than creating a new one — `initState` never re-runs.
    // This listener covers exactly that case: it fires whenever the pending
    // code changes while this page is already alive.
    ref.listen<String?>(pendingCouponCodeProvider, (previous, next) {
      if (next != null && next.isNotEmpty) {
        unawaited(_maybeApplyPendingCoupon());
      }
    });

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: AppLoadingPage(message: 'Preparing checkout summary...'),
      );
    }

    if (cartState.cart.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text('Checkout',
              style: AppTypography.titleLarge
                  .copyWith(fontWeight: FontWeight.bold)),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(AppIcons.back),
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                context.go(AppRoutes.home);
              }
            },
          ),
          backgroundColor: Colors.white,
          elevation: 0,
        ),
        body: AppEmptyState(
          icon: AppIcons.cartOutlined,
          title: 'Nothing to checkout',
          subtitle:
              'Add laundry services from a vendor before scheduling pickup.',
          actionLabel: 'Browse vendors',
          onAction: () => context.go(AppRoutes.vendorListing),
        ),
      );
    }

    final hasAddress =
        _selectedAddress != null && _selectedAddress!.id.isNotEmpty;
    final hasPickupSelection = _isExpressPickup || _selectedSlot != null;
    final canProceed =
        hasAddress && hasPickupSelection && !_isPreparingCheckout;
    final ctaLabel = _isPreparingCheckout
        ? 'Preparing Checkout...'
        : (hasAddress && !hasPickupSelection)
            ? 'Select a pickup time to continue'
            : 'Proceed to Payment';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: CheckoutBrandHeader(
        isDark: isDark,
        subtitle: 'Secure payments powered by Razorpay',
        onBack: () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          } else {
            context.go(AppRoutes.home);
          }
        },
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.pagePaddingH.w,
                  AppSpacing.md.h,
                  AppSpacing.pagePaddingH.w,
                  AppSpacing.sm.h,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _heroHeader(),
                    Gap(AppSpacing.sectionGap.h),
                    _deliveryAddressCard(),
                    Gap(AppSpacing.cardGap.h),
                    _pickupModeCard(cartState),
                    Gap(AppSpacing.cardGap.h),
                    _vendorOrderCard(cartState),
                    Gap(AppSpacing.cardGap.h),
                    _pickupTimingCard(cartState),
                    Gap(AppSpacing.sectionGap.h),
                    _couponSection(),
                    Gap(AppSpacing.sectionGap.h),
                    _notesSection(),
                    Gap(AppSpacing.sectionGap.h),
                  ],
                ),
              ),
            ),
            _stickyBottomBar(
              cartState: cartState,
              canProceed: canProceed,
              ctaLabel: ctaLabel,
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SECTION BUILDERS — every section below is always present, in the same
  // fixed order, for every combination of Express / Anytime / Schedule.
  // Only the *inner content* of the pickup-timing card changes with mode.
  // ═══════════════════════════════════════════════════════════════════════

  Widget _heroHeader() {
    return Row(
      key: const ValueKey('checkout_hero_row'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Checkout',
                style: AppTypography.headlineLarge.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.lightTextPrimary,
                ),
              ),
              Gap(4.h),
              Text(
                'Almost there! Review your details and proceed.',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Gap(AppSpacing.sm.w),
        Image.asset(
          AssetConstants.paymentFreshTowelsBanner,
          height: 56.h,
          fit: BoxFit.contain,
        ),
      ],
    );
  }

  Widget _deliveryAddressCard() {
    return _premiumCard(
      cardKey: const ValueKey('checkout_delivery_address_card'),
      onTap: _showAddressModal,
      child: Row(
        children: [
          Container(
            width: 44.r,
            height: 44.r,
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.md.r),
            ),
            child:
                Icon(AppIcons.location, color: AppColors.primary, size: 22.r),
          ),
          Gap(AppSpacing.md.w),
          Expanded(
            child: _selectedAddress != null && _selectedAddress!.id.isNotEmpty
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Delivery Address',
                        style: AppTypography.labelMedium
                            .copyWith(color: AppColors.onSurfaceVariant),
                      ),
                      Gap(2.h),
                      Text(
                        _selectedAddress!.type.label,
                        style: AppTypography.titleSmall.copyWith(
                          color: AppColors.lightTextPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Gap(2.h),
                      Text(
                        '${_selectedAddress!.line1}, ${_selectedAddress!.city}',
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.onSurfaceVariant),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  )
                : Text(
                    'No address selected',
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textMuted),
                  ),
          ),
          Gap(AppSpacing.sm.w),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.sm.w,
              vertical: AppSpacing.xs.h,
            ),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.tag.r),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Change',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Icon(AppIcons.chevronRight,
                    size: 14.r, color: AppColors.primary),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pickupModeCard(CartState cartState) {
    final expressAvailable = cartState.vendor?.expressPickupAvailable ?? false;
    final expressLocked = _isApiMode && !expressAvailable;

    void toggleExpress(bool val) {
      setState(() {
        _isExpressPickup = val;
        _backendPricesLoaded = false;
        _orderDraftId = null;
      });
      if (_isApiMode) {
        unawaited(_refreshBackendQuote(cartState, silent: true));
      } else {
        unawaited(_loadBackendPrices());
      }
      if (val && _isApiMode) {
        unawaited(_loadPickupSlots());
      }
    }

    return _premiumCard(
      cardKey: const ValueKey('checkout_pickup_mode_card'),
      borderColor: _isExpressPickup ? AppColors.secondary : null,
      backgroundColor: _isExpressPickup
          ? AppColors.secondaryLight.withValues(alpha: 0.25)
          : null,
      onTap: () {
        if (expressLocked) {
          AppSnackBar.showError(
            context,
            'Express pickup is not available for this vendor.',
          );
          return;
        }
        toggleExpress(!_isExpressPickup);
      },
      child: Row(
        children: [
          Container(
            width: 44.r,
            height: 44.r,
            decoration: BoxDecoration(
              color: AppColors.secondaryLight,
              borderRadius: BorderRadius.circular(AppRadius.md.r),
            ),
            child: Icon(Icons.flash_on_rounded,
                color: AppColors.secondary, size: 22.r),
          ),
          Gap(AppSpacing.md.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pickup preference',
                  style: AppTypography.labelMedium
                      .copyWith(color: AppColors.onSurfaceVariant),
                ),
                Gap(2.h),
                Text(
                  '60-Min Express Pickup',
                  style: AppTypography.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.lightTextPrimary,
                  ),
                ),
                Gap(2.h),
                Text(
                  expressLocked
                      ? 'Not available for this vendor yet'
                      : _isExpressPickup
                          ? 'Express selected • additional charges apply'
                          : 'Pickup within 60 minutes',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Semantics(
            label: _isExpressPickup
                ? 'Express pickup, switched on'
                : 'Express pickup, switched off',
            child: Switch.adaptive(
              value: _isExpressPickup,
              activeThumbColor: AppColors.secondary,
              onChanged: expressLocked ? null : toggleExpress,
            ),
          ),
        ],
      ),
    );
  }

  /// Always-visible vendor + full item list — identical regardless of
  /// Express/Anytime/Schedule, driven entirely by the real cart model. Never
  /// hidden or restructured based on pickup mode.
  Widget _vendorOrderCard(CartState cartState) {
    final itemCount = cartState.cart.items.length;
    return _premiumCard(
      cardKey: const ValueKey('checkout_vendor_order_card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cartState.vendor != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40.r,
                  height: 40.r,
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    borderRadius: BorderRadius.circular(AppRadius.md.r),
                  ),
                  child: Icon(AppIcons.store,
                      size: 20.r, color: AppColors.primary),
                ),
                Gap(AppSpacing.sm.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cartState.vendor!.name,
                        style: AppTypography.titleSmall.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.lightTextPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Gap(2.h),
                      Text(
                        '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Gap(AppSpacing.sm.w),
                Image.asset(
                  AssetConstants.vendorStorefrontBadge,
                  height: 48.h,
                  fit: BoxFit.contain,
                ),
              ],
            ),
            Gap(AppSpacing.sm.h),
            Divider(color: AppColors.outlineVariant, thickness: 1, height: 1),
            Gap(AppSpacing.sm.h),
          ],
          ...cartState.cart.items.map((item) {
            final svc = cartState.services.firstWhere(
              (s) => s.id == item.serviceId,
              orElse: () => const ServiceModel(
                id: '',
                vendorId: '',
                name: 'Service',
                description: '',
                category: ServiceCategory.wash,
                minWeightKg: 0,
              ),
            );

            return Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xs.h),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          svc.name,
                          style: AppTypography.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.onSurface,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Gap(2.h),
                        Text(
                          'Qty ${item.quantity}',
                          style: AppTypography.caption
                              .copyWith(color: AppColors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Gap(AppSpacing.md.w),
                  Text(
                    ((svc.pricePerKg ?? svc.pricePerPiece ?? 0.0) *
                            item.quantity)
                        .toCurrencyDecimal,
                    style: AppTypography.titleSmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.lightTextPrimary,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  /// The pickup-timing card is ALWAYS present in the same position — only
  /// its inner content switches between the Express confirmation and the
  /// Anytime/Schedule picker. This is deliberate: the earlier version
  /// conditionally included/excluded whole cards from the scroll list,
  /// which let Flutter misattribute Elements across rebuilds and caused
  /// sections to render in the wrong place. A card that always exists,
  /// with only its child swapped, cannot do that.
  Widget _pickupTimingCard(CartState cartState) {
    // Deliberately NOT animated (no AnimatedSize/AnimatedSwitcher here).
    // When this content's size change coincided with another section
    // resizing in the same frame (e.g. Notes expanded while Express got
    // toggled), the engine hit a real, reproducible
    // "TransformLayer is constructed with an invalid matrix" error
    // (confirmed via logcat) that left this card's content stuck blank
    // and, in some cases, visibly displaced other sections. A plain,
    // un-animated swap is correct and cannot trigger that.
    return _premiumCard(
      cardKey: const ValueKey('checkout_pickup_timing_card'),
      child: _isExpressPickup
          ? _expressTimingContent()
          : _normalTimingContent(cartState),
    );
  }

  Widget _expressTimingContent() {
    return Row(
      key: const ValueKey('pickup_timing_express'),
      children: [
        Container(
          width: 40.r,
          height: 40.r,
          decoration: BoxDecoration(
            color: AppColors.secondaryLight,
            borderRadius: BorderRadius.circular(AppRadius.md.r),
          ),
          child:
              Icon(Icons.bolt_rounded, color: AppColors.secondary, size: 20.r),
        ),
        Gap(AppSpacing.sm.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Express pickup selected',
                style: AppTypography.titleSmall.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.lightTextPrimary,
                ),
              ),
              Gap(2.h),
              Text(
                'Expected pickup: within approximately 60 minutes.',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _normalTimingContent(CartState cartState) {
    final today = DateTime.now();
    final tomorrow = today.add(const Duration(days: 1));
    final anytimeWindow = _anytimeWindow();
    final scheduledSummary = _scheduledSlotSummary();

    return Column(
      key: const ValueKey('pickup_timing_normal'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(AppIcons.clock, size: 18.r, color: AppColors.primary),
            Gap(AppSpacing.xs.w),
            Expanded(
              child: Text(
                'Choose Pickup Time',
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.lightTextPrimary,
                ),
              ),
            ),
          ],
        ),
        Gap(2.h),
        Text(
          "Choose Anytime and we'll assign the best available pickup slot, or schedule a specific date and time.",
          style:
              AppTypography.caption.copyWith(color: AppColors.onSurfaceVariant),
        ),
        Gap(AppSpacing.cardGap.h),
        // NOTE: deliberately NOT CrossAxisAlignment.stretch — this Row sits
        // inside a MainAxisSize.min Column inside a SingleChildScrollView,
        // where "stretch" needs a bounded height to compute against and
        // instead produced a huge, invisible, mis-hitting tap target (the
        // actual root cause of "tapping Schedule does nothing" — confirmed
        // via the accessibility tree, whose reported bounds for these cards
        // extended ~800px below their visible edge). Both cards render to
        // the same natural height anyway, so no visual stretch is needed.
        Row(
          children: [
            Expanded(
              child: _PickupOptionCard(
                icon: Icons.flash_on_rounded,
                iconBackground: AppColors.secondaryLight,
                iconColor: AppColors.secondary,
                title: 'Anytime',
                subtitle: "We'll assign the best available pickup time.",
                isSelected: _pickupTimeMode == _PickupTimeMode.anytime,
                onTap: () => _setPickupTimeMode(_PickupTimeMode.anytime),
              ),
            ),
            Gap(AppSpacing.cardGap.w),
            Expanded(
              child: _PickupOptionCard(
                icon: AppIcons.calendar,
                iconBackground: AppColors.primaryContainer,
                iconColor: AppColors.primary,
                title: 'Schedule',
                subtitle: 'Choose a preferred date and time.',
                isSelected: _pickupTimeMode == _PickupTimeMode.schedule,
                onTap: () => _setPickupTimeMode(_PickupTimeMode.schedule),
              ),
            ),
          ],
        ),
        if (_pickupTimeMode == _PickupTimeMode.anytime) ...[
          Gap(AppSpacing.sm.h),
          Text(
            _isLoadingSlots
                ? 'Finding the best available slot...'
                : 'Available service window: ${anytimeWindow.rangeLabel}.',
            style: AppTypography.caption
                .copyWith(color: AppColors.onSurfaceVariant),
          ),
        ] else ...[
          Gap(AppSpacing.md.h),
          if (scheduledSummary != null) ...[
            _ScheduledSummaryStrip(
              summary: scheduledSummary,
              onChange: () => setState(() {}),
            ),
            Gap(AppSpacing.sm.h),
          ],
          Text('Select date',
              style: AppTypography.labelMedium
                  .copyWith(color: AppColors.onSurfaceVariant)),
          Gap(AppSpacing.sm.h),
          Row(
            children: [
              _DateChip(
                label: 'Today',
                subtitle: today.toDayMonth,
                isSelected: _selectedDateIdx == 0,
                onTap: () {
                  setState(() => _selectedDateIdx = 0);
                  unawaited(_loadPickupSlots());
                },
              ),
              Gap(AppSpacing.cardGap.w),
              _DateChip(
                label: 'Tomorrow',
                subtitle: tomorrow.toDayMonth,
                isSelected: _selectedDateIdx == 1,
                onTap: () {
                  setState(() => _selectedDateIdx = 1);
                  unawaited(_loadPickupSlots());
                },
              ),
            ],
          ),
          Gap(AppSpacing.md.h),
          Text('Available pickup slots',
              style: AppTypography.labelMedium
                  .copyWith(color: AppColors.onSurfaceVariant)),
          Gap(AppSpacing.sm.h),
          _slotGrid(),
        ],
      ],
    );
  }

  Widget _slotGrid() {
    if (_isApiMode && _isLoadingSlots) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg.h),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppLoadingIndicator(),
              Gap(AppSpacing.sm.h),
              Text(
                'Fetching available pickup times...',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    if (_isApiMode && _slotsLoadFailed) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg.h),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded,
                  size: 28.r, color: AppColors.onSurfaceVariant),
              Gap(AppSpacing.sm.h),
              Text(
                "Couldn't load pickup slots.\nPlease try again.",
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.onSurfaceVariant),
              ),
              Gap(AppSpacing.sm.h),
              AppButton.outlined(
                label: 'Retry',
                width: 120.w,
                height: 38.h,
                onPressed: () => unawaited(_loadPickupSlots()),
              ),
            ],
          ),
        ),
      );
    }

    if (_isApiMode && _pickupSlots.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg.h),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'No pickup slots are available for this date.',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              Gap(AppSpacing.xs.h),
              Text(
                'Please choose another date.',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    final itemCount = _isApiMode ? _pickupSlots.length : _slots.length;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10.w,
        mainAxisSpacing: 10.h,
        childAspectRatio: 2.8,
      ),
      itemCount: itemCount,
      itemBuilder: (context, idx) {
        final slot = _isApiMode ? _pickupSlots[idx].id : _slots[idx];
        final slotLabel = _isApiMode
            ? (_pickupSlots[idx].label ??
                AppDateUtils.formatTimeRange(
                  _pickupSlots[idx].startTime,
                  _pickupSlots[idx].endTime,
                ))
            : slot;
        final isChosen = _selectedSlot == slot;

        return Semantics(
          label: 'Pickup slot $slotLabel',
          selected: isChosen,
          child: GestureDetector(
            onTap: () {
              setState(() {
                _selectedSlot = slot;
                _backendPricesLoaded = false;
                _orderDraftId = null;
              });
              if (_isApiMode) {
                unawaited(_refreshBackendQuote(
                  ref.read(cartStateProvider),
                  silent: true,
                ));
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                color: isChosen ? AppColors.primaryContainer : Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.md.r),
                border: Border.all(
                  color:
                      isChosen ? AppColors.primary : AppColors.outlineVariant,
                  width: isChosen ? 1.5 : 1,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Center(
                    child: Text(
                      slotLabel,
                      style: AppTypography.labelMedium.copyWith(
                        color: isChosen
                            ? AppColors.primary
                            : AppColors.onSurfaceVariant,
                        fontWeight:
                            isChosen ? FontWeight.w700 : FontWeight.normal,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (isChosen)
                    Positioned(
                      right: 6.w,
                      top: 6.h,
                      child: Icon(Icons.check_circle_rounded,
                          size: 14.r, color: AppColors.primary),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _couponSection() {
    return KeyedSubtree(
      key: const ValueKey('checkout_coupon_section'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: _fieldSectionHeader(
                    icon: AppIcons.coupon, label: 'Coupon & Offers'),
              ),
              TextButton(
                onPressed: () => context.push(AppRoutes.offers),
                child: Text(
                  'View all',
                  style: AppTypography.labelMedium
                      .copyWith(color: AppColors.primary),
                ),
              ),
            ],
          ),
          Gap(AppSpacing.cardGap.h),
          if (_couponApplied)
            _CouponAppliedStrip(
              code: _couponController.text.trim().toUpperCase(),
              savedAmount: _backendDiscount,
              onRemove: () {
                setState(() {
                  _couponApplied = false;
                  _backendDiscount = 0;
                  _backendDiscountReason = null;
                  if (_backendPricesLoaded) {
                    _backendTotal = _localTotalWithDiscount(0);
                  }
                  _couponController.clear();
                  _couponExpanded = false;
                });
                // Re-resolve the authoritative total now that no coupon is
                // active — this is also what lets a still-eligible
                // first-order free-delivery offer fold back in automatically
                // (prepareOrder omits `couponCode` once `_couponApplied` is
                // false), instead of leaving delivery paid-for until some
                // unrelated field change happens to trigger a refresh.
                if (_isApiMode) {
                  unawaited(
                    _refreshBackendQuote(
                      ref.read(cartStateProvider),
                      silent: true,
                    ),
                  );
                }
              },
            )
          else if (!_couponExpanded)
            _CollapsedActionRow(
              icon: AppIcons.coupon,
              label: 'Apply coupon',
              onTap: () => setState(() => _couponExpanded = true),
            )
          else
            _CouponSection(
              controller: _couponController,
              focusNode: _couponFocusNode,
              isFocused: _couponFocused,
              isLoading: _isCouponValidating,
              onFocusChange: (v) => setState(() => _couponFocused = v),
              onApply: _onApplyCoupon,
            ),
        ],
      ),
    );
  }

  Widget _notesSection() {
    final hasNote = _notesController.text.trim().isNotEmpty;
    return KeyedSubtree(
      key: const ValueKey('checkout_notes_section'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _fieldSectionHeader(
              icon: Icons.notes_rounded, label: 'Pickup Instructions'),
          Gap(AppSpacing.cardGap.h),
          if (!_notesExpanded)
            _CollapsedActionRow(
              icon: Icons.notes_rounded,
              label: hasNote
                  ? _notesController.text.trim()
                  : 'Add instructions for pickup or delivery',
              labelMaxLines: hasNote ? 2 : 1,
              trailingLabel: 'Optional',
              onTap: () => setState(() => _notesExpanded = true),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.md.r),
                border: Border.all(color: AppColors.outlineVariant),
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _notesController,
                    maxLines: 3,
                    minLines: 3,
                    maxLength: _notesMaxLength,
                    autofillHints: const <String>[],
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText:
                          'e.g. Call before arriving, use side entrance...',
                      hintStyle: AppTypography.bodyMedium
                          .copyWith(color: AppColors.lightTextHint),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      counterText: '',
                      contentPadding: EdgeInsets.fromLTRB(
                        AppSpacing.md.r,
                        AppSpacing.md.r,
                        AppSpacing.md.r,
                        0,
                      ),
                    ),
                    style: AppTypography.bodyMedium
                        .copyWith(color: AppColors.lightTextPrimary),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.md.r,
                      0,
                      AppSpacing.md.r,
                      AppSpacing.sm.r,
                    ),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${_notesController.text.length} / $_notesMaxLength',
                        style: AppTypography.caption
                            .copyWith(color: AppColors.onSurfaceVariant),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _stickyBottomBar({
    required CartState cartState,
    required bool canProceed,
    required String ctaLabel,
  }) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.pagePaddingH.w,
        AppSpacing.md.h,
        AppSpacing.pagePaddingH.w,
        MediaQuery.paddingOf(context).bottom + AppSpacing.md.h,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.dialog.r)),
        boxShadow: AppElevation.high,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_backendPricesLoaded) ...[
            Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.md.r),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.md.r),
                onTap: () =>
                    setState(() => _showBillDetails = !_showBillDetails),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.xs.h),
                  child: Row(
                    children: [
                      Container(
                        width: 38.r,
                        height: 38.r,
                        decoration: BoxDecoration(
                          color: AppColors.primaryContainer,
                          borderRadius: BorderRadius.circular(AppRadius.sm.r),
                        ),
                        child: Icon(AppIcons.wallet,
                            size: 19.r, color: AppColors.primary),
                      ),
                      Gap(AppSpacing.sm.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total Payable',
                              style: AppTypography.labelSmall
                                  .copyWith(color: AppColors.onSurfaceVariant),
                            ),
                            Gap(2.h),
                            Text(
                              _backendTotal.toCurrencyDecimal,
                              style: AppTypography.headlineMedium.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _showBillDetails ? 'Hide bill' : 'View bill',
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Icon(
                            _showBillDetails
                                ? AppIcons.chevronUp
                                : AppIcons.chevronDown,
                            size: 18.r,
                            color: AppColors.primary,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Deliberately not animated — see the note on
            // `_pickupTimingCard` above for why AnimatedSize is avoided on
            // this page.
            if (_showBillDetails)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Gap(AppSpacing.sm.h),
                  Divider(
                      color: AppColors.outlineVariant, thickness: 1, height: 1),
                  Gap(AppSpacing.xs.h),
                  _PriceRow(
                    icon: AppIcons.document,
                    label: 'Subtotal',
                    amount: _backendSubtotal,
                  ),
                  _PriceRow(
                    icon: Icons.local_shipping_outlined,
                    label: 'Delivery Fee',
                    amount: _backendDeliveryFee,
                  ),
                  _PriceRow(
                    icon: Icons.percent_rounded,
                    label: 'Taxes & Charges',
                    amount: _backendTaxes,
                  ),
                  if (_backendExpressFee > 0)
                    _PriceRow(
                      icon: Icons.bolt_rounded,
                      label: 'Express Pickup Fee',
                      amount: _backendExpressFee,
                    ),
                  for (final extra in _backendExtraCharges)
                    _PriceRow(
                      icon: _iconForFeeCode(extra.code),
                      label: extra.label,
                      amount: extra.amount,
                    ),
                  if (_backendDiscount > 0)
                    _PriceRow(
                      icon: AppIcons.tag,
                      label: 'Discount',
                      amount: -_backendDiscount,
                      valueColor: AppColors.success,
                    ),
                  if (_backendDiscount > 0 && _backendDiscountReason != null)
                    Padding(
                      padding: EdgeInsets.only(top: 2.h),
                      child: Text(
                        _backendDiscountReason!,
                        style: AppTypography.caption
                            .copyWith(color: AppColors.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
          ] else if (_isApiMode) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Estimated Total',
                    style: AppTypography.titleSmall.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.lightTextPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Gap(AppSpacing.md.w),
                Text(
                  cartState.total.toCurrencyDecimal,
                  style: AppTypography.headlineSmall.copyWith(
                      color: AppColors.primary, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            Gap(AppSpacing.xs.h),
            Text(
              'Final amount is confirmed by the backend before payment.',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.onSurfaceVariant, height: 1.4),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Total Estimated Price',
                    style: AppTypography.titleSmall.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.lightTextPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Gap(AppSpacing.md.w),
                Text(
                  (_isApiMode
                          ? _backendTotal
                          : cartState.total + (_isExpressPickup ? 99.0 : 0.0))
                      .toCurrencyDecimal,
                  style: AppTypography.headlineSmall.copyWith(
                      color: AppColors.primary, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ],
          Gap(AppSpacing.md.h),
          _CheckoutGradientButton(
            label: ctaLabel,
            isBusy: _isPreparingCheckout,
            onPressed: canProceed ? () => _onProceedToPayment(cartState) : null,
          ),
          Gap(AppSpacing.sm.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.verified_user_rounded,
                  size: 12.r, color: AppColors.onSurfaceVariant),
              Gap(4.w),
              Text(
                '100% secure payments powered by Razorpay',
                style: AppTypography.caption
                    .copyWith(color: AppColors.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Shared premium card shell used across every checkout section — soft
  /// shadow, no harsh visible border in light mode, matching the reference
  /// design instead of the old flat outlined cards.
  Widget _premiumCard({
    required Widget child,
    Key? cardKey,
    VoidCallback? onTap,
    Color? borderColor,
    Color? backgroundColor,
  }) {
    return Material(
      key: cardKey,
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.xl.r),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.xl.r),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(AppSpacing.md.r),
          decoration: BoxDecoration(
            color: backgroundColor ?? Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.xl.r),
            boxShadow: AppElevation.low,
            border: Border.all(
              color: borderColor ?? Colors.transparent,
              width: borderColor != null ? 1.5 : 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _fieldSectionHeader({required IconData icon, required String label}) {
    return Row(
      children: [
        Icon(icon, size: 18.r, color: AppColors.primary),
        Gap(AppSpacing.xs.w),
        Text(
          label,
          style: AppTypography.titleMedium.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.lightTextPrimary,
          ),
        ),
      ],
    );
  }
}

/// Maps a backend fee code (see `FEE_CODES` in the fee-settings/totals
/// engine) to a fitting icon for the sticky summary bar.
IconData _iconForFeeCode(String code) => switch (code) {
      'PLATFORM_FEE' => Icons.dashboard_customize_rounded,
      'HANDLING_FEE' => Icons.build_circle_outlined,
      'SMALL_CART_FEE' => Icons.shopping_basket_outlined,
      'SURGE_FEE' => Icons.bolt_rounded,
      'PACKAGING_FEE' => Icons.inventory_2_outlined,
      _ => Icons.receipt_long_outlined,
    };

// ═══════════════════════════════════════════════════════════════════════════
// COLLAPSED ACTION ROW — shared by Coupon and Notes when not expanded
// ═══════════════════════════════════════════════════════════════════════════

class _CollapsedActionRow extends StatelessWidget {
  const _CollapsedActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailingLabel,
    this.labelMaxLines = 1,
  });

  final IconData icon;
  final String label;
  final String? trailingLabel;
  final int labelMaxLines;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.md.r),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md.r),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.md.w,
            vertical: AppSpacing.sm.h,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md.r),
            border: Border.all(color: AppColors.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18.r, color: AppColors.onSurfaceVariant),
              Gap(AppSpacing.sm.w),
              Expanded(
                child: Text(
                  label,
                  maxLines: labelMaxLines,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyMedium
                      .copyWith(color: AppColors.lightTextBody),
                ),
              ),
              if (trailingLabel != null) ...[
                Text(
                  trailingLabel!,
                  style: AppTypography.caption
                      .copyWith(color: AppColors.onSurfaceVariant),
                ),
                Gap(4.w),
              ],
              Icon(AppIcons.chevronRight,
                  size: 16.r, color: AppColors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// COUPON APPLIED STRIP
// ═══════════════════════════════════════════════════════════════════════════

class _CouponAppliedStrip extends StatelessWidget {
  const _CouponAppliedStrip({
    required this.code,
    required this.savedAmount,
    required this.onRemove,
  });

  final String code;
  final double savedAmount;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.md.w,
        vertical: AppSpacing.sm.h,
      ),
      decoration: BoxDecoration(
        color: AppColors.successContainer,
        borderRadius: BorderRadius.circular(AppRadius.md.r),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(AppIcons.coupon, size: 18.r, color: AppColors.success),
          Gap(AppSpacing.sm.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  code,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (savedAmount > 0)
                  Text(
                    '${savedAmount.toCurrencyDecimal} saved',
                    style: AppTypography.caption
                        .copyWith(color: AppColors.success),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: onRemove,
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm.w),
              minimumSize: Size(0, 36.h),
            ),
            child: Text(
              'Remove',
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SCHEDULED SUMMARY STRIP
// ═══════════════════════════════════════════════════════════════════════════

class _ScheduledSummaryStrip extends StatelessWidget {
  const _ScheduledSummaryStrip({required this.summary, required this.onChange});

  final String summary;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.md.w,
        vertical: AppSpacing.sm.h,
      ),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.md.r),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded,
              size: 18.r, color: AppColors.primary),
          Gap(AppSpacing.sm.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pickup scheduled',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  summary,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// APP BAR, PICKUP OPTION CARD, RADIO DOT, GRADIENT BUTTON
// ═══════════════════════════════════════════════════════════════════════════

class _PickupOptionCard extends StatelessWidget {
  const _PickupOptionCard({
    required this.icon,
    required this.iconBackground,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final Color iconBackground;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$title pickup, ${isSelected ? 'selected' : 'not selected'}',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.all(AppSpacing.sm.r),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryContainer : Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.lg.r),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.outlineVariant,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PickupRadioDot(isSelected: isSelected),
                  Gap(AppSpacing.xs.w),
                  Container(
                    width: 32.r,
                    height: 32.r,
                    decoration: BoxDecoration(
                      color: iconBackground,
                      borderRadius: BorderRadius.circular(AppRadius.sm.r),
                    ),
                    child: Icon(icon, size: 16.r, color: iconColor),
                  ),
                ],
              ),
              Gap(AppSpacing.xs.h),
              Text(
                title,
                style: AppTypography.titleSmall.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.lightTextPrimary,
                ),
              ),
              Gap(2.h),
              Text(
                subtitle,
                style: AppTypography.caption
                    .copyWith(color: AppColors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickupRadioDot extends StatelessWidget {
  const _PickupRadioDot({required this.isSelected});

  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18.r,
      height: 18.r,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? AppColors.primary : AppColors.outline,
          width: 2,
        ),
      ),
      child: isSelected
          ? Center(
              child: Container(
                width: 9.r,
                height: 9.r,
                decoration: const BoxDecoration(
                    color: AppColors.primary, shape: BoxShape.circle),
              ),
            )
          : null,
    );
  }
}

class _CheckoutGradientButton extends StatelessWidget {
  const _CheckoutGradientButton({
    required this.label,
    required this.isBusy,
    required this.onPressed,
  });

  final String label;
  final bool isBusy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final isDisabled = onPressed == null;
    return Opacity(
      opacity: isDisabled ? 0.55 : 1,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.full.r),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.full.r),
          onTap: onPressed,
          child: Container(
            height: 54.h,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: AppColors.signInCtaGradient,
              borderRadius: BorderRadius.circular(AppRadius.full.r),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: AppTypography.buttonText.copyWith(
                        color: Colors.white, fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                Gap(8.w),
                if (isBusy)
                  SizedBox(
                    width: 16.r,
                    height: 16.r,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                else if (!isDisabled)
                  Icon(Icons.arrow_forward_rounded,
                      color: Colors.white, size: 18.r),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// COUPON INPUT (expanded state)
// ═══════════════════════════════════════════════════════════════════════════

class _CouponSection extends StatefulWidget {
  const _CouponSection({
    required this.controller,
    required this.focusNode,
    required this.isFocused,
    required this.onFocusChange,
    required this.onApply,
    this.isLoading = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isFocused;
  final bool isLoading;
  final ValueChanged<bool> onFocusChange;
  final VoidCallback onApply;

  @override
  State<_CouponSection> createState() => _CouponSectionState();
}

class _CouponSectionState extends State<_CouponSection> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    widget.focusNode.addListener(_onFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    widget.focusNode.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  void _onFocusChanged() {
    if (mounted) widget.onFocusChange(widget.focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(AppSpacing.sm.r),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md.r),
        border: Border.all(
          color:
              widget.isFocused ? AppColors.primary : AppColors.outlineVariant,
          width: widget.isFocused ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Padding(
            padding: EdgeInsets.only(left: AppSpacing.sm.w),
            child: Icon(
              AppIcons.coupon,
              size: 20.r,
              color: widget.isFocused
                  ? AppColors.primary
                  : AppColors.onSurfaceVariant,
            ),
          ),
          Gap(AppSpacing.sm.w),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              autofillHints: const <String>[],
              decoration: InputDecoration(
                hintText: 'Enter coupon code',
                hintStyle: AppTypography.bodyMedium
                    .copyWith(color: AppColors.lightTextHint),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.lightTextPrimary),
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (widget.controller.text.trim().isNotEmpty) widget.onApply();
              },
            ),
          ),
          SizedBox(
            height: 44.h,
            child: AppButton(
              label: 'Apply',
              width: 72.w,
              height: 44.h,
              isLoading: widget.isLoading,
              onPressed: (!widget.isLoading &&
                      widget.controller.text.trim().isNotEmpty)
                  ? widget.onApply
                  : null,
              isDisabled: widget.controller.text.trim().isEmpty,
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.md.w),
              textStyle: AppTypography.labelMedium
                  .copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PRICE ROW
// ═══════════════════════════════════════════════════════════════════════════

class _PriceRow extends StatelessWidget {
  const _PriceRow({
    required this.label,
    required this.amount,
    this.icon,
    this.valueColor,
  });

  final String label;
  final double amount;
  final IconData? icon;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.xs.h),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14.r, color: AppColors.onSurfaceVariant),
            Gap(6.w),
          ],
          Expanded(
            child: Text(
              label,
              style:
                  AppTypography.bodySmall.copyWith(color: AppColors.onSurface),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Gap(AppSpacing.sm.w),
          Text(
            amount.toCurrencyDecimal,
            style: AppTypography.labelMedium.copyWith(
              fontWeight: FontWeight.w600,
              color: valueColor ?? AppColors.lightTextPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// QUOTE INPUT
// ═══════════════════════════════════════════════════════════════════════════

class _QuoteInput {
  const _QuoteInput({
    required this.vendorId,
    required this.vendorServiceId,
    required this.lines,
  });

  final String vendorId;
  final String? vendorServiceId;
  final List<QuoteGarmentLine> lines;
}

// ═══════════════════════════════════════════════════════════════════════════
// CHARGE LINE — one itemized real backend fee (platform/portal, packaging,
// handling, small-cart, surge — whichever the vendor/admin has enabled).
// ═══════════════════════════════════════════════════════════════════════════

class _ChargeLine {
  const _ChargeLine({
    required this.code,
    required this.label,
    required this.amount,
  });

  final String code;
  final String label;
  final double amount;
}

// ═══════════════════════════════════════════════════════════════════════════
// CHECKOUT AMOUNTS
// ═══════════════════════════════════════════════════════════════════════════

class _CheckoutAmounts {
  const _CheckoutAmounts({
    required this.subtotal,
    required this.deliveryFee,
    required this.taxes,
    required this.expressFee,
    required this.discount,
    required this.total,
    required this.discountReason,
    required this.extraCharges,
  });

  factory _CheckoutAmounts.fromDraft(OrderDraftResult draft) {
    final snapshot = draft.snapshot ?? const <String, dynamic>{};
    final feeBreakdown =
        snapshot['fee_breakdown'] as Map<String, dynamic>? ?? const {};
    final quote = snapshot['quote'] as Map<String, dynamic>? ?? const {};

    final subtotalPaise = _readPaise(
      feeBreakdown,
      const ['subtotal_paise', 'subtotal'],
      fallback: _readPaise(quote, const ['estimate_paise']),
    );
    final deliveryPaise =
        _readPaise(feeBreakdown, const ['delivery_fee_paise', 'delivery_fee']);
    final taxPaise =
        _readPaise(feeBreakdown, const ['tax_paise', 'tax', 'tax_paise_total']);
    final expressFeePaise =
        _readPaise(feeBreakdown, const ['express_fee_paise']);
    final discountPaise = _readPaise(
      feeBreakdown,
      const ['discount_paise', 'discount', 'discount_paise_total'],
    );
    final totalPaise = _readPaise(
      feeBreakdown,
      const ['total_payable_paise', 'payable_amount_paise', 'total'],
      fallback: draft.payableAmountPaise,
    );

    return _CheckoutAmounts(
      subtotal: subtotalPaise / 100.0,
      deliveryFee: deliveryPaise / 100.0,
      taxes: taxPaise / 100.0,
      expressFee: expressFeePaise / 100.0,
      discount: discountPaise / 100.0,
      total: totalPaise / 100.0,
      discountReason: _readDiscountReason(snapshot, discountPaise),
      extraCharges: _readExtraCharges(feeBreakdown),
    );
  }

  final double subtotal;
  final double deliveryFee;
  final double taxes;
  final double expressFee;
  final double discount;
  final double total;
  final String? discountReason;
  final List<_ChargeLine> extraCharges;

  static int _readPaise(
    Map<String, dynamic> json,
    List<String> keys, {
    int fallback = 0,
  }) {
    for (final key in keys) {
      final value = json[key];
      if (value is num) return value.toInt();
    }
    return fallback;
  }

  /// Reads the itemized `canonical_breakdown.fees[]` array the backend's
  /// TotalsEngine produces (already in rupees, unlike the sibling `_paise`
  /// rollup fields) and returns only the entries not already represented by
  /// the fixed Subtotal/Delivery Fee/Taxes rows — e.g. platform ("portal")
  /// fee, packaging fee, handling fee, small-cart fee, surge fee — and only
  /// when the vendor/admin has actually enabled them (amount > 0).
  static List<_ChargeLine> _readExtraCharges(
      Map<String, dynamic> feeBreakdown) {
    final canonical =
        feeBreakdown['canonical_breakdown'] as Map<String, dynamic>?;
    final feesRaw = canonical?['fees'] as List<dynamic>?;
    if (feesRaw == null) return const [];

    const alreadyShown = {'DELIVERY_FEE', 'GST'};
    final result = <_ChargeLine>[];
    for (final entry in feesRaw) {
      if (entry is! Map) continue;
      final code = entry['code']?.toString() ?? '';
      if (code.isEmpty || alreadyShown.contains(code)) continue;
      final amount = (entry['amount'] as num?)?.toDouble() ?? 0;
      if (amount <= 0) continue;
      result.add(_ChargeLine(
        code: code,
        label: entry['label']?.toString() ?? 'Additional charge',
        amount: amount,
      ));
    }
    return result;
  }

  /// Discounts on this screen can come from three independent sources —
  /// a manually-entered coupon, or one of two auto-applied rewards
  /// (first-order offer / spend milestone) that need no code at all. The
  /// bill summary was showing a bare "-₹X" with no indication of which
  /// one fired, so this resolves a human-readable reason from the same
  /// draft snapshot the discount amount itself came from.
  static String? _readDiscountReason(
    Map<String, dynamic> snapshot,
    int discountPaise,
  ) {
    if (discountPaise <= 0) return null;

    final couponCode = snapshot['coupon_code'] as String?;
    if (couponCode != null && couponCode.isNotEmpty) {
      return 'Coupon "$couponCode" applied';
    }

    final firstTimeOffer =
        snapshot['first_time_offer'] as Map<String, dynamic>?;
    if (firstTimeOffer != null) {
      final name = firstTimeOffer['name'] as String?;
      return name != null && name.isNotEmpty
          ? '$name — first order offer'
          : 'First order offer applied';
    }

    final cartMilestone = snapshot['cart_milestone'] as Map<String, dynamic>?;
    if (cartMilestone != null) {
      final name = cartMilestone['name'] as String?;
      return name != null && name.isNotEmpty
          ? '$name — spend reward'
          : 'Spend milestone reward applied';
    }

    return null;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DATE CHIP
// ═══════════════════════════════════════════════════════════════════════════

class _DateChip extends StatelessWidget {
  const _DateChip({
    required this.label,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(vertical: AppSpacing.sm.h),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryContainer : Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.md.r),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.outlineVariant,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: AppTypography.labelLarge.copyWith(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.lightTextPrimary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              Gap(AppSpacing.xs.h),
              Text(
                subtitle,
                style: AppTypography.caption.copyWith(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
