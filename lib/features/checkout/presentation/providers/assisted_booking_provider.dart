import '../../../../core/design/design_system.dart';
import '../../../../repositories/repositories.dart';

/// "Book With Expert Check" config for one vendor — whether the vendor offers
/// it, and the admin-editable wording (dashboard → Categories → Assisted
/// Booking). Re-fetched each time a screen that needs it opens (autoDispose),
/// so an admin edit shows up without an app update. On any failure it yields
/// an *unavailable* config, so the option simply doesn't appear.
final assistedBookingConfigProvider = FutureProvider.autoDispose
    .family<AssistedBookingConfig, String>((ref, vendorId) async {
  if (vendorId.isEmpty) return AssistedBookingConfig.fallback;
  try {
    return await ref
        .read(customerRepositoryProvider)
        .getAssistedBookingConfig(vendorId);
  } catch (_) {
    return AssistedBookingConfig.fallback;
  }
});
