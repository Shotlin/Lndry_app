import 'package:flutter/widgets.dart';
import '../../models/models.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// A location just confirmed on the map step, carried to the form-only
/// second step (see [MapAddressArgs.prefilledLocation]) — everything a
/// reverse-geocode already resolved, so the form step never shows a map,
/// only the remaining flat/house number the geocoder could never know.
typedef MapPrefilledLocation = ({
  double lat,
  double lng,
  String formattedAddress,
  String city,
  String state,
  String pincode,
});

/// `extra` payload for [AppRoutes.mapAddress] — omit entirely for a fresh
/// add (map shown). Pass [existingAddress] to skip the map and prefill the
/// form from an already-saved address, with [isEditingExisting] only
/// controlling the heading ("Edit Address" vs "Select Delivery Location").
/// Pass [prefilledLocation] instead to skip the map for a *new*,
/// not-yet-saved address whose coordinates were just confirmed on the map
/// step — unlike [existingAddress], this still creates a new address on
/// save rather than updating one. [requireFlatNumber] should only ever be
/// true for the checkout completeness guard — every other entry point
/// (signup/location capture, saved-address add/edit) must allow saving
/// with an empty flat/house number.
typedef MapAddressArgs = ({
  AddressModel? existingAddress,
  bool isEditingExisting,
  bool requireFlatNumber,
  MapPrefilledLocation? prefilledLocation,
});

/// LNDRY Route Path Constants
/// Matches the canonical route inventory in spec Appendix B.
abstract final class AppRoutes {
  AppRoutes._();

  // ── Auth & Onboarding ─────────────────────────────────────────────────────
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String otp = '/otp';
  static const String profileSetup = '/profile-setup';
  static const String locationPermission = '/location-permission';
  static const String mapAddress = '/map-address';

  // ── Dashboard Tabs ────────────────────────────────────────────────────────
  static const String home = '/home';
  static const String lastOrderReview = '/home/last-order-review';
  static const String search = '/search';
  static const String cart = '/cart';
  static const String orders = '/orders';
  static const String profile = '/profile';

  // ── Discovery ─────────────────────────────────────────────────────────────
  static const String category = '/category/:categoryId';
  static const String vendorListing = '/vendors';
  static const String vendorDetails = '/vendor/:vendorId';

  // ── Checkout / Booking ────────────────────────────────────────────────────
  static const String checkout = '/checkout';
  static const String payment = '/checkout/payment';

  // ── Orders ────────────────────────────────────────────────────────────────
  /// Post-payment confirmation: /orders/:orderId/submitted
  static const String orderConfirmation = '/orders/:orderId/submitted';

  /// Order detail + tracking: registered as sub-route 'details/:orderId'
  /// under /orders, so full path = /orders/details/:orderId.
  static const String orderDetails = '/orders/details/:orderId';

  // ── Profile sub-routes ─────────────────────────────────────────────────────
  static const String editProfile = '/profile/edit';
  static const String address = '/profile/address';
  static const String notifications = '/profile/notifications';
  static const String myReviews = '/profile/reviews';
  static const String settings = '/profile/settings';
  static const String help = '/profile/help';
  static const String offers = '/profile/offers';
  static const String wallet = '/profile/wallet';
  static const String referEarn = '/profile/refer-earn';
}

/// LNDRY Route Name Constants (for named navigation via context.goNamed).
abstract final class AppRouteNames {
  AppRouteNames._();

  static const String splash = 'splash';
  static const String onboarding = 'onboarding';
  static const String login = 'login';
  static const String otp = 'otp';
  static const String profileSetup = 'profile-setup';
  static const String locationPermission = 'location-permission';
  static const String mapAddress = 'map-address';

  static const String home = 'home';
  static const String lastOrderReview = 'last-order-review';
  static const String search = 'search';
  static const String cart = 'cart';
  static const String orders = 'orders';
  static const String profile = 'profile';

  static const String category = 'category';
  static const String vendorListing = 'vendor-listing';
  static const String vendorDetails = 'vendor-details';

  static const String checkout = 'checkout';
  static const String payment = 'payment';
  static const String orderConfirmation = 'order-confirmation';
  static const String orderDetails = 'order-details';

  static const String editProfile = 'edit-profile';
  static const String address = 'address';
  static const String notifications = 'notifications';
  static const String myReviews = 'my-reviews';
  static const String settings = 'settings';
  static const String help = 'help';
  static const String offers = 'offers';
  static const String wallet = 'wallet';
  static const String referEarn = 'refer-earn';
}
