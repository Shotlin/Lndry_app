import '../../../../core/constants/asset_constants.dart';
import '../../../../core/theme/theme.dart';
import '../../../../providers/auth_provider.dart';

/// Full-screen location permission experience shown immediately after signup.
///
/// This widget deliberately owns presentation only. The existing auth state
/// transitions and address-selection API are unchanged.
class LocationPermissionPage extends ConsumerStatefulWidget {
  const LocationPermissionPage({super.key});

  @override
  ConsumerState<LocationPermissionPage> createState() =>
      _LocationPermissionPageState();
}

class _LocationPermissionPageState
    extends ConsumerState<LocationPermissionPage> {
  bool _isLoading = false;

  Future<void> _onGrantPermission() async {
    setState(() => _isLoading = true);
    await Future<void>.delayed(const Duration(milliseconds: 1000));

    if (!mounted) return;
    setState(() => _isLoading = false);
    await ref.read(authProvider.notifier).completeLocationSetup();
    if (mounted) context.push(AppRoutes.mapAddress);
  }

  Future<void> _onManualEntry() async {
    await ref.read(authProvider.notifier).completeLocationSetup();
    if (mounted) context.push(AppRoutes.mapAddress);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCFCFF),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 760;
            final horizontal = constraints.maxWidth > 600 ? 72.0 : 24.0;

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(horizontal, 12.h, horizontal, 20.h),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 32.h,
                  maxWidth: 880,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TopBar(onClose: _onManualEntry),
                    SizedBox(height: compact ? 24.h : 38.h),
                    _BrandLockup(),
                    SizedBox(height: compact ? 24.h : 34.h),
                    Text(
                      'Allow location access',
                      textAlign: TextAlign.left,
                      style: AppTypography.displayMedium.copyWith(
                        color: const Color(0xFF14234B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 14.h),
                    Text(
                      'We’ll use your location to find the nearest laundry partners and schedule faster pickups.',
                      style: AppTypography.bodyLarge.copyWith(
                        color: const Color(0xFF5E6C89),
                        height: 1.65,
                      ),
                    ),
                    SizedBox(height: compact ? 24.h : 34.h),
                    _LocationHero(compact: compact),
                    SizedBox(height: compact ? 24.h : 30.h),
                    const _BenefitRow(),
                    SizedBox(height: compact ? 24.h : 32.h),
                    _UseLocationButton(
                      isLoading: _isLoading,
                      onPressed: _onGrantPermission,
                    ),
                    SizedBox(height: 14.h),
                    _ManualLocationButton(onPressed: _onManualEntry),
                    SizedBox(height: 18.h),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_outline_rounded,
                            size: 18.r, color: const Color(0xFF5D45D8)),
                        SizedBox(width: 8.w),
                        Flexible(
                          child: Text(
                            'Your location is only used to improve your experience.',
                            textAlign: TextAlign.center,
                            style: AppTypography.bodySmall.copyWith(
                              color: const Color(0xFF5E6C89),
                              fontSize: 12.sp,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Semantics(
          button: true,
          label: 'Close location access',
          child: IconButton(
            onPressed: onClose,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFF4F2FF),
              foregroundColor: const Color(0xFF14234B),
              fixedSize: Size(54.r, 54.r),
            ),
            icon: Icon(Icons.close_rounded, size: 29.r),
          ),
        ),
      ],
    );
  }
}

class _BrandLockup extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Image.asset(AssetConstants.logoFull, width: 54.r, height: 54.r),
        SizedBox(width: 10.w),
        Text('Lndry',
            style: AppTypography.displaySmall.copyWith(
              color: const Color(0xFF5D45D8),
              fontWeight: FontWeight.w700,
            )),
      ],
    );
  }
}

class _LocationHero extends StatelessWidget {
  const _LocationHero({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28.r),
      child: AspectRatio(
        aspectRatio: compact ? 2.4 : 2.05,
        child: Image.asset(
          'assets/images/img/loc_pop_icon.png',
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          semanticLabel: 'LNDRY location map illustration',
        ),
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow();

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.gps_fixed_rounded, 'Find nearby', 'laundries', Color(0xFFECE9FF), Color(0xFF5D45D8)),
      (Icons.delivery_dining_rounded, 'Faster', 'pickups', Color(0xFFE5F8FB), Color(0xFF1599B3)),
      (Icons.verified_user_rounded, 'Secure &', 'private', Color(0xFFECE9FF), Color(0xFF5D45D8)),
    ];

    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          Expanded(
            child: Column(
              children: [
                Container(
                  width: 66.r,
                  height: 66.r,
                  decoration: BoxDecoration(
                    color: items[i].$4,
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Icon(items[i].$1, color: items[i].$5, size: 32.r),
                ),
                SizedBox(height: 12.h),
                Text(items[i].$2,
                    style: AppTypography.titleMedium.copyWith(
                      color: const Color(0xFF14234B),
                    )),
                Text(items[i].$3,
                    style: AppTypography.bodyMedium.copyWith(
                      color: const Color(0xFF5E6C89),
                    )),
              ],
            ),
          ),
          if (i != items.length - 1)
            Container(width: 1, height: 68.h, color: const Color(0xFFE6E3F8)),
        ],
      ],
    );
  }
}

class _UseLocationButton extends StatelessWidget {
  const _UseLocationButton({required this.isLoading, required this.onPressed});
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 68.h,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF9078FF), Color(0xFF5538DB)],
          ),
          borderRadius: BorderRadius.circular(36.r),
          boxShadow: const [
            BoxShadow(color: Color(0x3D7154E8), blurRadius: 20, offset: Offset(0, 10)),
          ],
        ),
        child: ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(36.r)),
          ),
          child: isLoading
              ? const CircularProgressIndicator(color: Colors.white)
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Use current location', style: AppTypography.titleLarge.copyWith(color: Colors.white)),
                    SizedBox(width: 22.w),
                    Container(
                      width: 48.r,
                      height: 48.r,
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: Icon(Icons.near_me_rounded, color: const Color(0xFF5D45D8), size: 25.r),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ManualLocationButton extends StatelessWidget {
  const _ManualLocationButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 68.h,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF5D45D8),
          side: const BorderSide(color: Color(0xFFBFB5FF), width: 1.6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.r)),
        ),
        child: Row(
          children: [
            Icon(Icons.location_on_outlined, size: 28.r),
            Expanded(
              child: Text('Enter location manually', textAlign: TextAlign.center,
                  style: AppTypography.titleLarge.copyWith(color: const Color(0xFF5D45D8))),
            ),
            Icon(Icons.chevron_right_rounded, size: 32.r),
          ],
        ),
      ),
    );
  }
}
