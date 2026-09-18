import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/asset_constants.dart';
import '../../../../core/design/design_system.dart';
import '../../../../core/extensions/extensions.dart';

/// Shared Lndry-branded header used across the checkout → payment flow:
/// round back button, wordmark + "Secure ... powered by Razorpay" line, and
/// the "Cleaner Days Ahead" cursive tag — kept in one place so both screens
/// stay pixel-identical instead of drifting apart over separate edits.
class CheckoutBrandHeader extends StatelessWidget implements PreferredSizeWidget {
  const CheckoutBrandHeader({
    super.key,
    required this.isDark,
    required this.onBack,
    required this.subtitle,
  });

  final bool isDark;
  final VoidCallback onBack;
  final String subtitle;

  @override
  Size get preferredSize => Size.fromHeight(96.h);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        height: preferredSize.height,
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.md.w),
        color: isDark ? AppColors.darkBackground : Colors.white,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  AssetConstants.logoWordmark,
                  height: 34.h,
                  fit: BoxFit.contain,
                ),
                const Gap(6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_rounded,
                        size: 11.r, color: AppColors.onSurfaceVariant),
                    const Gap(4),
                    Text(
                      subtitle,
                      style: AppTypography.caption
                          .copyWith(color: AppColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: CheckoutCircleIconButton(icon: AppIcons.back, onTap: onBack),
            ),
            Positioned(
              right: 4.w,
              top: 4.h,
              child: Transform.rotate(
                angle: -0.08,
                child: Text(
                  'Cleaner\nDays Ahead',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.caveat(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurfaceVariant.withValues(alpha: 0.7),
                    height: 1.05,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CheckoutCircleIconButton extends StatelessWidget {
  const CheckoutCircleIconButton({super.key, required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 38.r,
          height: 38.r,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDark
                ? AppColors.darkSurfaceContainer
                : AppColors.primaryContainer,
          ),
          child: Icon(icon, size: 16.r, color: AppColors.primary),
        ),
      ),
    );
  }
}
