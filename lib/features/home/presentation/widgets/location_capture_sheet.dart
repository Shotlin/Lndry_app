import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../config/env.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/theme/theme.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../models/models.dart';
import '../../../../providers/auth_provider.dart';
import '../../../address/address_serviceability_validator.dart';
import '../../../address/location_capture_service.dart';
import '../providers/home_providers.dart';

/// Shows the premium "auto-detect my location" bottom sheet.
///
/// Returns `true` only when the user chose "Enter Address Manually" — the
/// caller is responsible for the follow-up navigation to the map page,
/// mirroring the `requireAuthenticated`/`_LoginPromptSheet` pattern in
/// `core/auth/auth_gate.dart`.
Future<bool> showLocationCaptureSheet(
  BuildContext context, {
  bool isReprompt = false,
}) async {
  final wantsManualEntry = await AppBottomSheet.show<bool>(
    context: context,
    title: isReprompt
        ? 'Location Access Turned Off'
        : 'Set Your Delivery Location',
    isScrollControlled: true,
    child: _LocationCaptureSheetContent(isReprompt: isReprompt),
  );
  return wantsManualEntry == true;
}

enum _LocationSheetError {
  none,
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  geocodeFailed,
  notServiceable,
  network,
  unknown,
}

class _LocationCaptureSheetContent extends ConsumerStatefulWidget {
  const _LocationCaptureSheetContent({required this.isReprompt});

  final bool isReprompt;

  @override
  ConsumerState<_LocationCaptureSheetContent> createState() =>
      _LocationCaptureSheetContentState();
}

class _LocationCaptureSheetContentState
    extends ConsumerState<_LocationCaptureSheetContent> {
  bool _isLoading = false;
  String? _errorMessage;
  _LocationSheetError _errorKind = _LocationSheetError.none;

  Future<void> _onUseCurrentLocation() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _errorKind = _LocationSheetError.none;
    });

    try {
      final captured = await ref
          .read(locationCaptureServiceProvider)
          .captureCurrentLocation();

      if (!Env.shouldBypassServiceability) {
        final error =
            await ref.read(addressServiceabilityValidatorProvider).validate(
                  lat: captured.latitude,
                  lng: captured.longitude,
                  pincode: captured.pincode,
                );
        if (error != null) {
          if (mounted) {
            setState(() {
              _errorMessage = error;
              _errorKind = _LocationSheetError.notServiceable;
            });
          }
          return;
        }
      }

      final user = ref.read(currentUserProvider);
      final address = AddressModel(
        id: '',
        userId: user?.id ?? '',
        // Deliberately blank, not `captured.line1` — that's just the
        // GPS-reverse-geocoded street/locality name, not a real flat/house
        // number. Auto-filling it here meant every auto-detected address
        // silently "had" a flat number that was never actually the user's,
        // so the checkout completeness guard could never catch it. Leave
        // it empty; the guard sends them to fill in the real one before
        // their first order.
        line1: '',
        line2: captured.formattedAddress.isNotEmpty
            ? captured.formattedAddress
            : null,
        city: captured.city,
        state: captured.state.isNotEmpty ? captured.state : captured.city,
        pincode: captured.pincode,
        landmark: null,
        type: AddressType.home,
        isDefault: true,
        coordinates: LatLng(
          latitude: captured.latitude,
          longitude: captured.longitude,
        ),
      );

      await ref.read(authProvider.notifier).completeAddressSelection(address);

      ref
        ..invalidate(currentAddressProvider)
        ..invalidate(homeVendorsProvider)
        ..invalidate(homeCategoriesProvider);

      await ref
          .read(storageServiceProvider)
          .saveBool(AppConstants.keyLocationRepromptShown, value: false);

      if (mounted) {
        AppSnackBar.showSuccess(
          context,
          'Location detected and saved as your default address.',
        );
        Navigator.of(context).pop();
      }
    } on LocationServiceOffException catch (e) {
      _setError(e.message, _LocationSheetError.serviceDisabled);
    } on LocationPermissionDeniedForeverException catch (e) {
      _setError(e.message, _LocationSheetError.permissionDeniedForever);
    } on LocationPermissionDeniedException catch (e) {
      _setError(e.message, _LocationSheetError.permissionDenied);
    } on ReverseGeocodeFailedException catch (e) {
      _setError(e.message, _LocationSheetError.geocodeFailed);
    } on DioException {
      _setError(
        'Could not save your address. Please check your connection and try again.',
        _LocationSheetError.network,
      );
    } catch (_) {
      _setError('Something went wrong. Please try again.',
          _LocationSheetError.unknown);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _setError(String message, _LocationSheetError kind) {
    if (!mounted) return;
    setState(() {
      _errorMessage = message;
      _errorKind = kind;
    });
  }

  Future<void> _onOpenSettings() async {
    if (_errorKind == _LocationSheetError.serviceDisabled) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    final showOpenSettings =
        _errorKind == _LocationSheetError.serviceDisabled ||
            _errorKind == _LocationSheetError.permissionDeniedForever;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24.r),
            child: AspectRatio(
              aspectRatio: 2.35,
              child: Image.asset(
                'assets/images/img/loc_pop_icon.png',
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                semanticLabel: 'LNDRY location map illustration',
              ),
            ),
          ),
          Gap(20.h),
          Text(
            widget.isReprompt
                ? 'We noticed location access is off. Turn it back on so we can '
                    'keep your delivery address accurate.'
                : 'Let LNDRY auto-detect your address so we can find nearby '
                    'laundry partners and get your pickup scheduled in seconds.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.onSurfaceVariant,
              height: 1.6,
            ),
          ),
          if (_errorMessage != null) ...[
            Gap(16.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.md.r),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(AppIcons.warning, size: 18.r, color: AppColors.error),
                  Gap(8.w),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.error),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Gap(32.h),
          _SheetGradientButton(
            isLoading: _isLoading,
            onPressed: _onUseCurrentLocation,
          ),
          if (showOpenSettings) ...[
            Gap(12.h),
            AppButton.outlined(
              label: _errorKind == _LocationSheetError.serviceDisabled
                  ? 'Open Location Settings'
                  : 'Open App Settings',
              onPressed: _onOpenSettings,
            ),
          ],
          Gap(12.h),
          SizedBox(
            height: 58.h,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: Icon(Icons.location_on_outlined, size: 24.r),
              label: Expanded(
                child: Text(
                  'Enter location manually',
                  textAlign: TextAlign.center,
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: Color(0xFFBFB5FF), width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22.r),
                ),
              ),
            ),
          ),
          Gap(4.h),
          Align(
            alignment: Alignment.center,
            child: Text(
              'Your location is only used to improve your experience.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetGradientButton extends StatelessWidget {
  const _SheetGradientButton(
      {required this.isLoading, required this.onPressed});

  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60.h,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF9078FF), Color(0xFF5538DB)],
          ),
          borderRadius: BorderRadius.circular(32.r),
          boxShadow: const [
            BoxShadow(
              color: Color(0x3D7154E8),
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(32.r),
            ),
          ),
          child: isLoading
              ? const CircularProgressIndicator(color: Colors.white)
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Use current location',
                      style: AppTypography.titleMedium.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 16.w),
                    Container(
                      width: 42.r,
                      height: 42.r,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.near_me_rounded,
                        color: Color(0xFF5D45D8),
                        size: 22,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
