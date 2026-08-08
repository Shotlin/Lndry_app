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
    title: isReprompt ? 'Location Access Turned Off' : 'Set Your Delivery Location',
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
      final captured =
          await ref.read(locationCaptureServiceProvider).captureCurrentLocation();

      if (!Env.shouldBypassServiceability) {
        final error = await ref.read(addressServiceabilityValidatorProvider).validate(
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
        line1: captured.line1,
        line2: captured.formattedAddress.isNotEmpty ? captured.formattedAddress : null,
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
      _setError('Something went wrong. Please try again.', _LocationSheetError.unknown);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final showOpenSettings = _errorKind == _LocationSheetError.serviceDisabled ||
        _errorKind == _LocationSheetError.permissionDeniedForever;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 96.r,
              height: 96.r,
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkSurfaceContainerHigh
                    : AppColors.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                AppIcons.location,
                size: 44.r,
                color: AppColors.primary,
              ),
            ),
          ),
          Gap(24.h),
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
                      style: AppTypography.bodySmall.copyWith(color: AppColors.error),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Gap(32.h),
          AppButton(
            label: 'Use Current Location',
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
          AppButton.text(
            label: 'Enter Address Manually',
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
  }
}
