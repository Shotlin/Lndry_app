import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/models.dart';

/// Category artwork that is always available: the photos from the Lndry API
/// are bundled in `assets/images/categories/`, so something real paints on the
/// very first frame (no network, no empty circle). If the backend serves a
/// newer image for the category it fades in over the bundled one.
class CategoryImage extends StatelessWidget {
  const CategoryImage({
    super.key,
    required this.category,
    required this.size,
  });

  final CategoryModel category;
  final double size;

  static String _slug(String name) => name
      .toLowerCase()
      .replaceAll('&', ' ')
      .replaceAll(RegExp(r"[^a-z0-9]+"), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  /// Bundled photo for [name], or null for a category added after this build.
  static String? bundledAsset(String name) {
    final slug = _slug(name);
    return _bundledSlugs.contains(slug)
        ? 'assets/images/categories/$slug.jpg'
        : null;
  }

  static const _bundledSlugs = {
    'laundry-service',
    'mens-wear-dry-cleaning',
    'womens-wear-dry-cleaning',
    'household-dry-cleaning',
    'accessories-dry-cleaning',
  };

  /// Cloudinary serves the 800px original; ask for a small square instead.
  static String _thumb(String url) {
    const marker = '/image/upload/';
    final i = url.indexOf(marker);
    if (i < 0 || !url.contains('res.cloudinary.com')) return url;
    final at = i + marker.length;
    return '${url.substring(0, at)}w_360,h_360,c_fill,${url.substring(at)}';
  }

  @override
  Widget build(BuildContext context) {
    final asset = bundledAsset(category.name);
    final local = asset == null
        ? Container(
            width: size,
            height: size,
            color: const Color(0xFFF1EFFE),
            child: Icon(Icons.local_laundry_service_rounded,
                size: size * 0.45, color: const Color(0xFF6B4FF0)),
          )
        : Image.asset(asset, width: size, height: size, fit: BoxFit.cover);

    final remote = (category.imageUrl ?? '').trim();
    // The bundled photo is the same picture the backend serves; only hit the
    // network for categories we don't have bundled.
    if (asset != null || !remote.startsWith('http')) return local;
    return CachedNetworkImage(
      imageUrl: _thumb(remote),
      width: size,
      height: size,
      fit: BoxFit.cover,
      memCacheWidth: 360,
      placeholder: (_, __) => local,
      errorWidget: (_, __, ___) => local,
    );
  }
}

/// Seed list so the home/search category rails render instantly (and still
/// work offline) before the API answers. Ids match production.
const bundledCategories = <CategoryModel>[
  CategoryModel(
      id: '83cebe9a-bfe6-49e0-a3cf-cbccaa841e2f',
      name: 'Laundry Service',
      description: '',
      icon: 'laundry'),
  CategoryModel(
      id: 'b337d98f-a589-4fbc-a58d-d9184a38d814',
      name: "Men's Wear Dry Cleaning",
      description: 'Shirts, suits and everyday menswear dry cleaning',
      icon: 'dry',
      sortOrder: 1),
  CategoryModel(
      id: '28ce6fd3-3e53-4225-8ec0-88f17a717362',
      name: "Women's Wear Dry Cleaning",
      description: 'Sarees, dresses and everyday womenswear dry cleaning',
      icon: 'dry',
      sortOrder: 2),
  CategoryModel(
      id: '738c17c1-9d0f-4301-9751-266303c1a9a7',
      name: 'Household Dry Cleaning',
      description: 'Bedsheets, blankets, quilts and other home textiles',
      icon: 'dry',
      sortOrder: 3),
  CategoryModel(
      id: '0d1694b3-30e2-4f38-b549-220b281c42a4',
      name: 'Accessories Dry Cleaning',
      description: 'Shoes, bags, toys and other accessories dry cleaning',
      icon: 'dry',
      sortOrder: 4),
];
