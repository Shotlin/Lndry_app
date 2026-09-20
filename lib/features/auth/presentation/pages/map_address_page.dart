import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../../../core/auth/auth_gate.dart';
import '../../../../core/network/network.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/theme.dart';
import '../../../../core/utils/location_service_resolver.dart';
import '../../../../core/utils/resilient_location.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../features/home/presentation/providers/home_providers.dart';
import '../../../../models/models.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../repositories/repositories.dart';
import '../../../../config/env.dart';
import '../../../../core/network/friendly_error.dart';

class MapAddressPage extends ConsumerStatefulWidget {
  const MapAddressPage({
    super.key,
    this.existingAddress,
    this.isEditingExisting = false,
    this.requireFlatNumber = false,
    this.prefilledLocation,
  });

  /// When set, the page skips the map-picking step entirely (coordinates
  /// are already known) and prefills the form from this address instead —
  /// used both to *complete* an address that's missing its flat number
  /// (checkout guard) and to *edit* an already-complete saved address.
  final AddressModel? existingAddress;

  /// When set (and [existingAddress] is null), the page skips the map step
  /// for a *new* address whose location was just confirmed on the map
  /// step — prefills address/city/state/pincode, leaves the flat/house
  /// number blank for the user to fill in, and still creates a new address
  /// on save (unlike [existingAddress], which updates one in place).
  final MapPrefilledLocation? prefilledLocation;

  /// Only affects the heading: true shows "Edit Address" (reached via an
  /// explicit edit action on a saved address), false shows "Select
  /// Delivery Location" (fresh add, or completing a missing flat number).
  /// Has no effect when [existingAddress] is null.
  final bool isEditingExisting;

  /// When true, saving is blocked until the flat/house number is filled in.
  /// Only the checkout completeness guard sets this — signup/location
  /// capture and saved-address add/edit must always allow an empty flat
  /// number, since that's only required to actually place an order.
  final bool requireFlatNumber;

  @override
  ConsumerState<MapAddressPage> createState() => _MapAddressPageState();
}

class _MapAddressPageState extends ConsumerState<MapAddressPage> {
  static const _initialCenter = ll.LatLng(20.5937, 78.9629);
  static const _initialZoom = 4.8;

  final _searchController = TextEditingController();
  final _addressLineController = TextEditingController();
  final _pincodeController = TextEditingController();
  final _landmarkController = TextEditingController();

  Timer? _searchDebounce;
  final _mapController = MapController();
  ll.LatLng? _pinPosition;
  String _selectedCity = '';
  String _selectedState = '';
  String _formattedAddress = '';
  AddressType _selectedType = AddressType.home;
  bool _isLoading = false;
  bool _isFetchingLocation = false;
  bool _isSearching = false;
  List<_PlaceSuggestion> _suggestions = const [];

  // Editable city / state controllers — pre-filled by reverse geocoding but
  // always editable so the user can correct auto-detection failures.
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();

  bool get _hasExisting => widget.existingAddress != null;

  /// True whenever the map step should be skipped entirely and only the
  /// detail form shown — either an already-saved address being edited/
  /// completed, or a brand-new location just confirmed on the map step.
  bool get _isFormOnly => _hasExisting || widget.prefilledLocation != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingAddress;
    final prefilled = widget.prefilledLocation;
    if (existing != null) {
      _addressLineController.text = existing.line1;
      _pincodeController.text = existing.pincode;
      _landmarkController.text = existing.landmark ?? '';
      _cityController.text = existing.city;
      _stateController.text = existing.state;
      _selectedCity = existing.city;
      _selectedState = existing.state;
      _selectedType = existing.type;
      _formattedAddress = existing.line2 ?? '';
      final coords = existing.coordinates;
      if (coords != null) {
        _pinPosition = ll.LatLng(coords.latitude, coords.longitude);
      }
    } else if (prefilled != null) {
      // Flat/house number deliberately left blank — a reverse-geocode can
      // never know it, and the user still needs to fill it in themselves.
      _pincodeController.text = prefilled.pincode;
      _cityController.text = prefilled.city;
      _stateController.text = prefilled.state;
      _selectedCity = prefilled.city;
      _selectedState = prefilled.state;
      _formattedAddress = prefilled.formattedAddress;
      _pinPosition = ll.LatLng(prefilled.lat, prefilled.lng);
    } else {
      unawaited(_moveToCurrentLocation());
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _addressLineController.dispose();
    _pincodeController.dispose();
    _landmarkController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    super.dispose();
  }

  Dio get _dio => ref.read(dioClientProvider);

  Map<String, dynamic> _dataMap(Response<dynamic> response) {
    final body = response.data as Map<String, dynamic>? ?? {};
    return body['data'] as Map<String, dynamic>? ?? {};
  }

  List<dynamic> _dataList(Response<dynamic> response) {
    final body = response.data as Map<String, dynamic>? ?? {};
    return body['data'] as List<dynamic>? ?? const [];
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    if (query.length < 3) {
      setState(() => _suggestions = const []);
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_loadSuggestions(query));
    });
  }

  Future<void> _loadSuggestions(String query) async {
    setState(() => _isSearching = true);
    try {
      final response = await _dio.get<dynamic>(
        '/maps/place-autocomplete',
        queryParameters: {
          'query': query,
          if (_pinPosition != null)
            'location_bias':
                '${_pinPosition!.latitude},${_pinPosition!.longitude}',
        },
      );
      final suggestions = _dataList(response)
          .map((e) => _PlaceSuggestion.fromJson(e as Map<String, dynamic>))
          .where((s) => !s.placeId.startsWith('mock_place_'))
          .toList();
      if (mounted) {
        setState(() => _suggestions = suggestions);
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(context, 'Could not load address suggestions.');
      }
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  Future<void> _selectSuggestion(_PlaceSuggestion suggestion) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _suggestions = const [];
      _searchController.text = suggestion.description;
      _isLoading = true;
    });

    try {
      double lat;
      double lng;
      String? postalCode;
      bool needsReverseGeocode;

      if (suggestion.lat != null && suggestion.lng != null) {
        // Ola-sourced — already carries everything, no second call needed.
        lat = suggestion.lat!;
        lng = suggestion.lng!;
        _formattedAddress = suggestion.formattedAddress ?? suggestion.description;
        postalCode = suggestion.postalCode;
        if (suggestion.city?.isNotEmpty == true) {
          _selectedCity = suggestion.city!;
          _cityController.text = suggestion.city!;
        }
        if (suggestion.state?.isNotEmpty == true) {
          _selectedState = suggestion.state!;
          _stateController.text = suggestion.state!;
        }
        needsReverseGeocode = false;
      } else {
        // Google-sourced fallback — needs the details + reverse-geocode
        // round trips, since autocomplete alone doesn't carry coordinates.
        final response = await _dio
            .get<dynamic>('/maps/place-details/${suggestion.placeId}');
        final details = _dataMap(response);
        final detailLat = (details['lat'] as num?)?.toDouble();
        final detailLng = (details['lng'] as num?)?.toDouble();
        if (detailLat == null || detailLng == null) {
          throw const FormatException('Selected place is missing coordinates.');
        }
        lat = detailLat;
        lng = detailLng;
        _formattedAddress =
            details['formatted_address'] as String? ?? suggestion.description;
        postalCode = details['postal_code'] as String?;
        needsReverseGeocode = true;
      }

      if (postalCode != null && postalCode.isNotEmpty) {
        _pincodeController.text = postalCode;
      }

      final next = ll.LatLng(lat, lng);
      await _setPin(next, zoom: 17);
      if (needsReverseGeocode) {
        await _reverseGeocode(next);
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(context, 'Could not resolve this address.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _moveToCurrentLocation() async {
    if (_isFetchingLocation) return;
    setState(() => _isFetchingLocation = true);

    try {
      var serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // Drives the native in-app "Turn on Location" dialog on Android
        // (genuinely flips GPS on without leaving the app) rather than
        // just telling the user to go do it themselves in Settings.
        serviceEnabled = await requestEnableLocationService();
        if (!serviceEnabled) {
          if (mounted) {
            AppSnackBar.showError(context, 'Please enable location services.');
          }
          return;
        }
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          AppSnackBar.showError(
            context,
            'Location permission is blocked. Enable it from app settings.',
          );
          unawaited(openLocationPermissionSettings());
        }
        return;
      }
      if (permission == LocationPermission.denied) {
        if (mounted) {
          AppSnackBar.showError(
            context,
            'Location permission is required to use current location.',
          );
        }
        return;
      }

      // Tiered fallback — a bare getCurrentPosition() right after enabling
      // GPS above regularly hangs while the OS location subsystem "warms
      // up", so this tries a cached fix, then low- then medium-accuracy
      // live fixes before giving up.
      final position = await getResilientCurrentPosition();
      final next = ll.LatLng(position.latitude, position.longitude);
      await _setPin(next, zoom: 17);
      await _reverseGeocode(next);
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(context, 'Could not fetch current location.');
      }
    } finally {
      if (mounted) {
        setState(() => _isFetchingLocation = false);
      }
    }
  }

  Future<void> _setPin(ll.LatLng position, {double? zoom}) async {
    setState(() => _pinPosition = position);
    _mapController.move(position, zoom ?? 16);
  }

  /// Reverse-geocodes via Ola Maps first (dashboard-configured; carries a
  /// landmark field the OS geocoder never provides, and is far more
  /// reliable for Indian addresses), falling back to the phone's own OS
  /// geocoder if Ola isn't configured/enabled or the call fails — so this
  /// never hard-breaks the address flow on a build where no one has set
  /// up an Ola Maps key in the dashboard yet.
  Future<void> _reverseGeocode(ll.LatLng position) async {
    if (await _reverseGeocodeViaOla(position)) return;
    await _reverseGeocodeViaOsGeocoder(position);
  }

  /// Returns true if Ola Maps successfully resolved and applied an
  /// address, false to signal the caller should fall back.
  Future<bool> _reverseGeocodeViaOla(ll.LatLng position) async {
    try {
      final response = await _dio.get<dynamic>(
        '/maps/ola/reverse-geocode',
        queryParameters: {'lat': position.latitude, 'lng': position.longitude},
      );
      final data = _dataMap(response);
      if (data.isEmpty || !mounted) return false;

      final resolvedCity = (data['city'] as String?)?.trim() ?? '';
      final resolvedState = (data['state'] as String?)?.trim() ?? '';
      final postalCode = (data['postal_code'] as String?)?.trim();
      final formatted = (data['formatted_address'] as String?)?.trim() ?? '';

      if (resolvedCity.isEmpty && formatted.isEmpty) return false;

      setState(() {
        if (resolvedCity.isNotEmpty) {
          _selectedCity = resolvedCity;
          _cityController.text = resolvedCity;
        }
        if (resolvedState.isNotEmpty) {
          _selectedState = resolvedState;
          _stateController.text = resolvedState;
        }
        if (_pincodeController.text.trim().isEmpty &&
            postalCode?.isNotEmpty == true) {
          _pincodeController.text = postalCode!;
        }
        if (_formattedAddress.isEmpty && formatted.isNotEmpty) {
          _formattedAddress = formatted;
        }
      });
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ReverseGeocode] Ola Maps failed, falling back: ${friendlyError(e)}');
      }
      return false;
    }
  }

  Future<void> _reverseGeocodeViaOsGeocoder(ll.LatLng position) async {
    try {
      final places = await geocoding.placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (places.isEmpty || !mounted) return;

      final place = places.first;

      // ── Debug: log the raw geocoder response ──────────────────────────────
      if (kDebugMode) {
        debugPrint(
          '[ReverseGeocode] Raw placemark for '
          '(${position.latitude}, ${position.longitude}):\n'
          '  name                  : ${place.name}\n'
          '  street                : ${place.street}\n'
          '  subLocality           : ${place.subLocality}\n'
          '  locality              : ${place.locality}\n'
          '  subAdministrativeArea : ${place.subAdministrativeArea}\n'
          '  administrativeArea    : ${place.administrativeArea}\n'
          '  postalCode            : ${place.postalCode}\n'
          '  country               : ${place.country}',
        );
      }

      // ── Robust city extraction: 4-level fallback chain ────────────────────
      // Android/iOS geocoders differ in which fields they populate for Indian
      // cities, so we try all meaningful fields before giving up.
      final String resolvedCity = _firstNonEmpty([
        place.locality,           // e.g. "Hyderabad", "Bengaluru"
        place.subAdministrativeArea, // e.g. "Hyderabad", "Bangalore Urban"
        place.administrativeArea, // e.g. "Telangana", "Karnataka" (last resort)
        place.subLocality,        // e.g. "LB Nagar"
      ]);

      final String resolvedState = _firstNonEmpty([
        place.administrativeArea, // e.g. "Telangana", "Karnataka"
        place.subAdministrativeArea,
        place.country,
      ]);

      if (kDebugMode) {
        debugPrint(
          '[ReverseGeocode] Resolved:\n'
          '  city    : $resolvedCity\n'
          '  state   : $resolvedState\n'
          '  pincode : ${place.postalCode}',
        );
      }

      setState(() {
        _selectedCity = resolvedCity;
        _selectedState = resolvedState;
        // Keep controller text in sync so the editable fields show the values.
        _cityController.text = resolvedCity;
        _stateController.text = resolvedState;

        // Only auto-fill pincode if the user hasn't typed one yet.
        if (_pincodeController.text.trim().isEmpty &&
            place.postalCode?.isNotEmpty == true) {
          _pincodeController.text = place.postalCode!;
        }

        // Build a human-readable formatted address from all available parts.
        if (_formattedAddress.isEmpty) {
          _formattedAddress = [
            place.name,
            place.street,
            place.subLocality,
            place.locality,
            place.administrativeArea,
          ].where((part) => part != null && part.trim().isNotEmpty).join(', ');
        }
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ReverseGeocode] Error: ${friendlyError(e)}');
      }
      if (mounted) {
        AppSnackBar.showError(context, 'Could not read address from map pin.');
      }
    }
  }

  /// Returns the first non-null, non-blank string from [candidates],
  /// or empty string if all are null/blank.
  static String _firstNonEmpty(List<String?> candidates) {
    for (final c in candidates) {
      if (c != null && c.trim().isNotEmpty) return c.trim();
    }
    return '';
  }

  /// Validates the selected coordinates and pincode against the backend.
  /// Returns null if serviceable, or a human-readable error message explaining
  /// exactly why the address was rejected.
  Future<String?> _validateBackendServiceability(ll.LatLng position) async {
    final pincode = _pincodeController.text.trim();

    // ── Log what we're about to send ──────────────────────────────────────────
    if (kDebugMode) {
      debugPrint(
        '[ServiceabilityCheck] Inputs:\n'
        '  lat         : ${position.latitude}\n'
        '  lng         : ${position.longitude}\n'
        '  pincode     : $pincode\n'
        '  city        : $_selectedCity\n'
        '  state       : $_selectedState\n'
        '  formatted   : $_formattedAddress',
      );
    }

    // ── Step 1: coordinate-based vendor proximity check ───────────────────────
    try {
      final locationPayload = {
        'lat': position.latitude,
        'lng': position.longitude,
      };
      if (kDebugMode) {
        debugPrint(
          '[ServiceabilityCheck] POST ${ApiEndpoints.validateLocation} '
          'payload: $locationPayload',
        );
      }

      final locationResponse = await _dio.post<dynamic>(
        ApiEndpoints.validateLocation,
        data: locationPayload,
      );
      final locationData = _dataMap(locationResponse);

      if (kDebugMode) {
        debugPrint(
          '[ServiceabilityCheck] validate-location response:\n'
          '  status      : ${locationResponse.statusCode}\n'
          '  body        : ${locationResponse.data}\n'
          '  serviceable : ${locationData["serviceable"]}\n'
          '  vendor_count: ${locationData["eligible_vendor_count"]}',
        );
      }

      final serviceable = locationData['serviceable'] as bool? ?? false;
      final vendorCount =
          (locationData['eligible_vendor_count'] as num?)?.toInt() ?? 0;

      if (!serviceable || vendorCount == 0) {
        return 'No laundry partners currently serve this location. '
            'Try a nearby address or check back later.';
      }
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[ServiceabilityCheck] validate-location FAILED: ${e.message}\n'
          '  response: ${e.response?.data}',
        );
      }
      return 'Serviceability check failed. Please check your connection and try again.';
    }

    // ── Step 2: pincode availability check ────────────────────────────────────
    try {
      final pincodePayload = {'pincode': pincode};
      if (kDebugMode) {
        debugPrint(
          '[ServiceabilityCheck] POST ${ApiEndpoints.validatePincode} '
          'payload: $pincodePayload',
        );
      }

      final pincodeResponse = await _dio.post<dynamic>(
        ApiEndpoints.validatePincode,
        data: pincodePayload,
      );
      final pincodeData = _dataMap(pincodeResponse);

      if (kDebugMode) {
        debugPrint(
          '[ServiceabilityCheck] validate-pincode response:\n'
          '  status    : ${pincodeResponse.statusCode}\n'
          '  body      : ${pincodeResponse.data}\n'
          '  available : ${pincodeData["available"]}',
        );
      }

      final available = pincodeData['available'] as bool? ?? false;
      if (!available) {
        return 'Delivery is not yet available in pincode $pincode. '
            'We are expanding — please check back soon.';
      }
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[ServiceabilityCheck] validate-pincode FAILED: ${e.message}\n'
          '  response: ${e.response?.data}',
        );
      }
      return 'Pincode check failed. Please check your connection and try again.';
    }

    // Both checks passed
    return null;
  }

  Future<void> _onSaveAddress() async {
    final line1 = _addressLineController.text.trim();
    final pincode = _pincodeController.text.trim();
    final pin = _pinPosition;

    if (pin == null) {
      AppSnackBar.showError(context, 'Please select your exact map location.');
      return;
    }
    if (pincode.isEmpty) {
      AppSnackBar.showError(context, 'Please complete the address details.');
      return;
    }
    // Flat/house number is only mandatory when arriving via the checkout
    // completeness guard — everywhere else (signup/location capture,
    // saved-address add/edit) an address may be saved without it.
    if (widget.requireFlatNumber && line1.isEmpty) {
      AppSnackBar.showError(
        context,
        'Please add your flat / house number to continue.',
      );
      return;
    }
    if (!RegExp(r'^[1-9][0-9]{5}$').hasMatch(pincode)) {
      AppSnackBar.showError(context, 'Please enter a valid 6 digit pincode.');
      return;
    }

    // If city wasn't auto-detected, use whatever the user has typed in the
    // editable city field. Do NOT block saving — the user should always be
    // able to complete an address manually.
    final cityFromController = _cityController.text.trim();
    if (_selectedCity.isEmpty && cityFromController.isNotEmpty) {
      _selectedCity = cityFromController;
    }
    final stateFromController = _stateController.text.trim();
    if (_selectedState.isEmpty && stateFromController.isNotEmpty) {
      _selectedState = stateFromController;
    }

    if (_selectedCity.isEmpty) {
      AppSnackBar.showError(
        context,
        'Please enter your city in the City field below.',
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (Env.shouldBypassServiceability) {
        // Development / QA bypass: skip the backend serviceability check so
        // any location can be used for testing without needing vendors nearby.
        // This branch is NEVER reached in release builds.
        if (kDebugMode) {
          debugPrint(
            '[DEV MODE] Serviceability check bypassed. '
            'Allowing address for testing.',
          );
        }
      } else {
        final error = await _validateBackendServiceability(pin);
        if (error != null) {
          if (mounted) {
            AppSnackBar.showError(context, error);
          }
          return;
        }
      }

      final existing = widget.existingAddress;
      final coordinates = LatLng(
        latitude: pin.latitude,
        longitude: pin.longitude,
      );
      final landmark = _landmarkController.text.trim().isEmpty
          ? null
          : _landmarkController.text.trim();
      final resolvedState =
          _selectedState.isNotEmpty ? _selectedState : _selectedCity;

      if (existing != null) {
        // Completing/editing an already-saved address — patch it in place,
        // preserving id/userId/isDefault, instead of creating a new one.
        final updated = existing.copyWith(
          line1: line1,
          line2: _formattedAddress.isNotEmpty ? _formattedAddress : null,
          city: _selectedCity,
          state: resolvedState,
          pincode: pincode,
          landmark: landmark,
          type: _selectedType,
          coordinates: coordinates,
        );
        await ref.read(customerRepositoryProvider).updateAddress(updated);

        ref
          ..invalidate(currentAddressProvider)
          ..invalidate(homeVendorsProvider)
          ..invalidate(homeCategoriesProvider);

        if (mounted) {
          AppSnackBar.showSuccess(context, 'Address updated.');
          Navigator.of(context).pop(updated);
        }
        return;
      }

      final user = ref.read(currentUserProvider);
      final address = AddressModel(
        id: '',
        userId: user?.id ?? '',
        line1: line1,
        line2: _formattedAddress.isNotEmpty ? _formattedAddress : null,
        city: _selectedCity,
        state: resolvedState,
        pincode: pincode,
        landmark: landmark,
        type: _selectedType,
        isDefault: true,
        coordinates: coordinates,
      );

      final hasPendingAction = ref.read(pendingAuthActionProvider) != null;
      await ref.read(authProvider.notifier).completeAddressSelection(address);

      // Invalidate every home-screen provider so the UI refreshes
      // immediately without an app restart.
      ref
        ..invalidate(currentAddressProvider)
        ..invalidate(homeVendorsProvider)
        ..invalidate(homeCategoriesProvider);

      if (mounted) {
        AppSnackBar.showSuccess(context, 'Address saved as default.');
        if (!hasPendingAction) {
          context.go(AppRoutes.home);
        }
      }
    } on DioException catch (e) {
      if (mounted) {
        AppSnackBar.showError(
          context,
          e.response?.data is Map<String, dynamic>
              ? ((e.response!.data as Map<String, dynamic>)['message']
                      as String? ??
                  'Failed to save address.')
              : 'Failed to save address.',
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(context, 'Failed to save address.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Pushes a fresh, map-free instance of this same page with the just-
  /// confirmed location prefilled — the "second page" the user fills in
  /// their flat/house number on. A new push (not an in-place state swap)
  /// so the back button naturally returns to the map with the pin/search
  /// state still intact, and so [_onSaveAddress]'s existing
  /// `context.go(AppRoutes.home)` on success correctly unwinds both this
  /// and the map page in one shot.
  void _onConfirmLocation() {
    final pin = _pinPosition;
    if (pin == null) return;
    context.push(
      AppRoutes.mapAddress,
      extra: (
        existingAddress: null,
        isEditingExisting: false,
        requireFlatNumber: widget.requireFlatNumber,
        prefilledLocation: (
          lat: pin.latitude,
          lng: pin.longitude,
          formattedAddress: _formattedAddress,
          city: _selectedCity,
          state: _selectedState,
          pincode: _pincodeController.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Landed here specifically to fill in a missing flat number (not a
    // general edit) — show the prominent purple-bordered callout.
    final showMissingFlatBanner = _hasExisting &&
        !widget.isEditingExisting &&
        widget.existingAddress!.line1.trim().isEmpty;

    final addressForm = _AddressForm(
      addressLineController: _addressLineController,
      pincodeController: _pincodeController,
      landmarkController: _landmarkController,
      cityController: _cityController,
      stateController: _stateController,
      selectedType: _selectedType,
      formattedAddress: _formattedAddress,
      city: _selectedCity,
      stateName: _selectedState,
      isLoading: _isLoading,
      saveLabel: _hasExisting ? 'Save Address' : 'Save Default Address',
      showMissingFlatBanner: showMissingFlatBanner,
      onTypeChanged: (type) => setState(() => _selectedType = type),
      onCityChanged: (v) => setState(() => _selectedCity = v),
      onStateChanged: (v) => setState(() => _selectedState = v),
      onSave: _onSaveAddress,
    );

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        title: Text(
          switch ((_hasExisting, widget.isEditingExisting, _isFormOnly)) {
            (true, true, _) => 'Edit Address',
            (false, _, true) => 'Confirm Address Details',
            _ => 'Select Delivery Location',
          },
          style: AppTypography.titleLarge,
        ),
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
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.surface,
        elevation: 0,
      ),
      body: SafeArea(
        child: _isFormOnly
            // Coordinates are already known — skip the map step entirely
            // and go straight to the form, matching a saved address's
            // "Edit" flow (and the checkout flat-number-completion guard).
            ? addressForm
            : Column(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _initialCenter,
                      initialZoom: _initialZoom,
                      // Tap or long-press to (re)place the pin — flutter_map
                      // has no built-in draggable marker like GoogleMap did,
                      // so re-tapping is how the pin gets repositioned now.
                      onTap: (tapPosition, point) async {
                        await _setPin(point);
                        await _reverseGeocode(point);
                      },
                      onLongPress: (tapPosition, point) async {
                        await _setPin(point);
                        await _reverseGeocode(point);
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.lndry.app',
                        maxZoom: 19,
                      ),
                      if (_pinPosition != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _pinPosition!,
                              width: 40.r,
                              height: 40.r,
                              // The pin icon's visual point sits at the
                              // bottom of its box, so anchor there — not
                              // flutter_map's Alignment.center default —
                              // or the tip would float above the real spot.
                              alignment: Alignment.bottomCenter,
                              child: Icon(
                                Icons.location_on_rounded,
                                color: AppColors.primary,
                                size: 40.r,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  Positioned(
                    left: 16.w,
                    right: 16.w,
                    top: 16.h,
                    child: Column(
                      children: [
                        Material(
                          elevation: 6,
                          borderRadius:
                              BorderRadius.circular(AppRadius.input.r),
                          color: isDark
                              ? AppColors.darkSurface
                              : AppColors.surface,
                          child: TextField(
                            controller: _searchController,
                            onChanged: _onSearchChanged,
                            textInputAction: TextInputAction.search,
                            decoration: InputDecoration(
                              hintText: 'Search address, building or area',
                              prefixIcon: const Icon(AppIcons.search),
                              suffixIcon: _isSearching
                                  ? Padding(
                                      padding: EdgeInsets.all(14.r),
                                      child: SizedBox(
                                        width: 16.r,
                                        height: 16.r,
                                        child: const CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    )
                                  : IconButton(
                                      icon: const Icon(AppIcons.close),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(
                                          () => _suggestions = const [],
                                        );
                                      },
                                    ),
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.input.r),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: isDark
                                  ? AppColors.darkSurface
                                  : AppColors.surface,
                            ),
                          ),
                        ),
                        if (_suggestions.isNotEmpty)
                          Container(
                            margin: EdgeInsets.only(top: 8.h),
                            constraints: BoxConstraints(maxHeight: 220.h),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppColors.darkSurface
                                  : AppColors.surface,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.card.r),
                              boxShadow: AppElevation.medium,
                            ),
                            child: ListView.separated(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: _suggestions.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final suggestion = _suggestions[index];
                                return ListTile(
                                  leading:
                                      const Icon(AppIcons.locationOutlined),
                                  title: Text(
                                    suggestion.description,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTypography.bodyMedium,
                                  ),
                                  onTap: () => _selectSuggestion(suggestion),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 16.w,
                    bottom: 16.h,
                    child: FloatingActionButton.small(
                      heroTag: 'current_location',
                      onPressed:
                          _isFetchingLocation ? null : _moveToCurrentLocation,
                      backgroundColor:
                          isDark ? AppColors.darkSurface : AppColors.surface,
                      foregroundColor: AppColors.primary,
                      child: _isFetchingLocation
                          ? SizedBox(
                              width: 18.r,
                              height: 18.r,
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(AppIcons.location),
                    ),
                  ),
                ],
              ),
            ),
            // Just a single "Confirm Location" action here — the map step
            // never shows the address form itself (that was the source of
            // the keyboard-squeezes-the-map bug: a tall form sharing this
            // screen with the map). Confirming pushes a fresh, map-free
            // instance of this same page with the resolved location
            // prefilled — see _onConfirmLocation.
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(
                AppSpacing.pagePaddingH.w,
                12.h,
                AppSpacing.pagePaddingH.w,
                12.h,
              ),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.surface,
                boxShadow: AppElevation.medium,
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_formattedAddress.isNotEmpty) ...[
                      Text(
                        _formattedAddress,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Gap(10.h),
                    ],
                    AppButton(
                      label: 'Confirm Location',
                      isDisabled: _pinPosition == null,
                      onPressed: _onConfirmLocation,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddressForm extends StatelessWidget {
  const _AddressForm({
    required this.addressLineController,
    required this.pincodeController,
    required this.landmarkController,
    required this.cityController,
    required this.stateController,
    required this.selectedType,
    required this.formattedAddress,
    required this.city,
    required this.stateName,
    required this.isLoading,
    required this.saveLabel,
    required this.showMissingFlatBanner,
    required this.onTypeChanged,
    required this.onCityChanged,
    required this.onStateChanged,
    required this.onSave,
  });

  final TextEditingController addressLineController;
  final TextEditingController pincodeController;
  final TextEditingController landmarkController;
  final TextEditingController cityController;
  final TextEditingController stateController;
  final AddressType selectedType;
  final String formattedAddress;
  final String city;
  final String stateName;
  final bool isLoading;
  final String saveLabel;
  final bool showMissingFlatBanner;
  final ValueChanged<AddressType> onTypeChanged;
  final ValueChanged<String> onCityChanged;
  final ValueChanged<String> onStateChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.pagePaddingH.w,
        vertical: AppSpacing.pagePaddingV.h,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.dialog.r),
        ),
        boxShadow: AppElevation.high,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showMissingFlatBanner) ...[
              Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.lg.r),
                  border: Border.all(color: AppColors.primary, width: 1.5),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: AppColors.primary,
                      size: 20.r,
                    ),
                    Gap(10.w),
                    Expanded(
                      child: Text(
                        'Your flat / house number is missing. Please add '
                        'it below to continue.',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.primaryDark,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Gap(16),
            ],
            Text('Confirm Location Details', style: AppTypography.titleMedium),
            if (formattedAddress.isNotEmpty) ...[
              const Gap(8),
              Text(
                formattedAddress,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            if (city.isNotEmpty || stateName.isNotEmpty) ...[
              const Gap(4),
              Text(
                [city, stateName]
                    .where((part) => part.trim().isNotEmpty)
                    .join(', '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
            ],
            const Gap(16),
            AppTextField(
              label: 'Flat / Building / House No.',
              hint: 'Enter your flat/house details',
              controller: addressLineController,
              textCapitalization: TextCapitalization.words,
            ),
            const Gap(12),
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    label: 'Pincode',
                    hint: '6 digits',
                    controller: pincodeController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: AppTextField(
                    label: 'Landmark',
                    hint: 'Near park',
                    controller: landmarkController,
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
              ],
            ),
            const Gap(12),
            // City + State — pre-filled by reverse geocoding, always editable
            // so the user can correct auto-detection failures.
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: AppTextField(
                    label: 'City *',
                    hint: 'e.g. Hyderabad',
                    controller: cityController,
                    textCapitalization: TextCapitalization.words,
                    onChanged: onCityChanged,
                  ),
                ),
                const Gap(12),
                Expanded(
                  flex: 3,
                  child: AppTextField(
                    label: 'State',
                    hint: 'e.g. Telangana',
                    controller: stateController,
                    textCapitalization: TextCapitalization.words,
                    onChanged: onStateChanged,
                  ),
                ),
              ],
            ),
            const Gap(16),
            Text('Save Address As', style: AppTypography.labelMedium),
            const Gap(8),
            Row(
              children: [
                _TypeButton(
                  label: 'Home',
                  icon: AppIcons.homeOutlined,
                  isSelected: selectedType == AddressType.home,
                  onTap: () => onTypeChanged(AddressType.home),
                ),
                const Gap(12),
                _TypeButton(
                  label: 'Work',
                  icon: AppIcons.store,
                  isSelected: selectedType == AddressType.work,
                  onTap: () => onTypeChanged(AddressType.work),
                ),
                const Gap(12),
                _TypeButton(
                  label: 'Other',
                  icon: AppIcons.locationOutlined,
                  isSelected: selectedType == AddressType.other,
                  onTap: () => onTypeChanged(AddressType.other),
                ),
              ],
            ),
            const Gap(20),
            AppButton(
              label: saveLabel,
              isLoading: isLoading,
              onPressed: onSave,
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeButton extends StatelessWidget {
  const _TypeButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AppButton.outlined(
        label: label,
        icon: Icon(
          icon,
          size: 16.r,
          color: isSelected ? AppColors.primary : AppColors.textSecondary,
        ),
        foregroundColor:
            isSelected ? AppColors.primary : AppColors.textSecondary,
        // Default OutlinedButton padding is too wide for 3 equal-width
        // buttons sharing one row — "Home"/"Other" were truncating to
        // "Ho..."/"Oth...". Tighter horizontal padding gives the label
        // room without needing to drop the icon.
        padding: EdgeInsets.symmetric(horizontal: 4.w),
        onPressed: onTap,
      ),
    );
  }
}

class _PlaceSuggestion {
  const _PlaceSuggestion({
    required this.description,
    required this.placeId,
    this.lat,
    this.lng,
    this.formattedAddress,
    this.postalCode,
    this.city,
    this.state,
  });

  factory _PlaceSuggestion.fromJson(Map<String, dynamic> json) {
    return _PlaceSuggestion(
      description: json['description'] as String? ?? '',
      placeId: json['place_id'] as String? ?? json['placeId'] as String? ?? '',
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      formattedAddress: json['formatted_address'] as String?,
      postalCode: json['postal_code'] as String?,
      city: json['city'] as String?,
      state: json['state'] as String?,
    );
  }

  final String description;
  final String placeId;

  /// Present only for Ola-sourced suggestions, whose geocode response
  /// already carries everything a details lookup would give — when set,
  /// [_MapAddressPageState._selectSuggestion] uses these directly instead
  /// of round-tripping through `/place-details` (which also can't safely
  /// carry a long encoded id in its URL — see maps.routes.js).
  final double? lat;
  final double? lng;
  final String? formattedAddress;
  final String? postalCode;
  final String? city;
  final String? state;
}
