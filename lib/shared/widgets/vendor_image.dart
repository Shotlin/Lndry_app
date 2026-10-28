import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Default artwork (Lndry brand logo on the brand gradient) shown whenever a
/// vendor has not uploaded their own photo, or the upload is still loading /
/// fails to load. Vendor-uploaded images always take priority.
class VendorImage extends StatelessWidget {
  const VendorImage({
    super.key,
    required this.url,
    this.logo = false,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  /// Vendor-uploaded image URL (banner or logo). Null/blank → default art.
  final String? url;

  /// Use the square brand logo default instead of the wide banner default.
  final bool logo;
  final BoxFit fit;
  final double? width;
  final double? height;

  static const bannerAsset = 'assets/images/img/vendor_default_banner.jpg';
  static const logoAsset = 'assets/images/img/vendor_default_logo.png';

  @override
  Widget build(BuildContext context) {
    // White artwork: scale it to fit whole (never crop the logo) inside tall,
    // wide or square slots alike.
    final fallback = ColoredBox(
      color: Colors.white,
      child: Image.asset(
        logo ? logoAsset : bannerAsset,
        width: width,
        height: height,
        fit: BoxFit.contain,
      ),
    );
    final u = url?.trim();
    if (u == null || !u.startsWith('http')) return fallback;
    return CachedNetworkImage(
      imageUrl: u,
      width: width,
      height: height,
      fit: fit,
      placeholder: (_, __) => fallback,
      errorWidget: (_, __, ___) => fallback,
    );
  }
}
