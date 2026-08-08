import '../../core/design/design_system.dart';

/// Brand tone for [Premium3DIcon] — purple is the default/primary tone,
/// aqua is used to alternate visual rhythm across a row/grid of icons
/// (e.g. the benefits grid) without introducing any off-brand colors.
enum Premium3DIconTone { purple, aqua }

/// LNDRY's custom 3D icon system: a single rounded "satin/plastic" object
/// with a gradient fill, a soft top-left specular highlight sweep, and a
/// natural drop shadow — used everywhere a bespoke branded icon is called
/// for (booking selectors, benefit cards, special offers) instead of a
/// flat Material icon or a glass-bubble wrapper around one.
///
/// Every usage shares the same perspective (highlight always top-left),
/// lighting (same highlight/shadow opacities) and corner-radius ratio, so
/// a row of different icons reads as one consistent icon family.
class Premium3DIcon extends StatelessWidget {
  const Premium3DIcon({
    super.key,
    required this.icon,
    this.tone = Premium3DIconTone.purple,
    this.size = 40,
    this.iconSize,
    this.radius,
  });

  final IconData icon;
  final Premium3DIconTone tone;
  final double size;
  final double? iconSize;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final isAqua = tone == Premium3DIconTone.aqua;
    final deep = isAqua ? AppColors.aquaDeep : AppColors.primaryDark;
    final mid = isAqua ? AppColors.aqua : AppColors.primary;
    final glow = isAqua ? AppColors.aqua : AppColors.primary;
    final boxSize = size.r;
    final cornerRadius = (radius ?? size * 0.32).r;

    return Container(
      width: boxSize,
      height: boxSize,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [mid, deep],
        ),
        borderRadius: BorderRadius.circular(cornerRadius),
        boxShadow: [
          BoxShadow(
            color: glow.withValues(alpha: 0.32),
            blurRadius: size * 0.34,
            offset: Offset(0, size * 0.12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(cornerRadius),
        child: Stack(
          children: [
            // Specular highlight — same top-left sweep on every icon so the
            // whole family reads as one lighting setup.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: boxSize * 0.55,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.white.withValues(alpha: 0.45),
                      AppColors.white.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            Center(
              child: Icon(
                icon,
                size: (iconSize ?? size * 0.48).r,
                color: AppColors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
