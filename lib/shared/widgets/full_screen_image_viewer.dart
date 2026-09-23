import '../../core/design/design_system.dart';

/// Full-screen viewer for re-evaluation evidence photos (and any other photo
/// strip that wants it) — tap a thumbnail to open the original image at
/// maximum usable size, pinch-zoom, pan while zoomed, swipe between photos
/// in the same set, and close with the top-right X. Purely a viewer: it
/// never navigates away from the screen underneath (opened as a dialog
/// route, popped to return to it with all state intact).
class FullScreenImageViewer {
  FullScreenImageViewer._();

  static void show(
    BuildContext context, {
    required List<String> images,
    int initialIndex = 0,
  }) {
    if (images.isEmpty) return;
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (context, animation, __) => FadeTransition(
          opacity: animation,
          child: _ImageViewerPage(
            images: images,
            initialIndex: initialIndex.clamp(0, images.length - 1),
          ),
        ),
      ),
    );
  }
}

class _ImageViewerPage extends StatefulWidget {
  const _ImageViewerPage({required this.images, required this.initialIndex});

  final List<String> images;
  final int initialIndex;

  @override
  State<_ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<_ImageViewerPage> {
  late final PageController _pageController =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: widget.images.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => _ZoomableImage(url: widget.images[i]),
            ),
            Positioned(
              top: 8.h,
              right: 8.w,
              child: _CloseButton(
                onTap: () => Navigator.of(context, rootNavigator: true).pop(),
              ),
            ),
            if (widget.images.length > 1)
              Positioned(
                bottom: 20.h,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(AppRadius.full.r),
                    ),
                    child: Text(
                      '${_index + 1} / ${widget.images.length}',
                      style: AppTypography.bodySmall.copyWith(color: AppColors.white),
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

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(8.r),
          child: Icon(Icons.close_rounded, color: AppColors.white, size: 24.r),
        ),
      ),
    );
  }
}

/// One page of the viewer — pinch-to-zoom + pan via [InteractiveViewer],
/// with the image's real aspect ratio (no forced crop, unlike the small
/// [BoxFit.cover] thumbnail this was opened from) and clean loading/error
/// states.
class _ZoomableImage extends StatelessWidget {
  const _ZoomableImage({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: 1,
      maxScale: 5,
      child: Center(
        child: Image.network(
          url,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return SizedBox(
              width: 40.r,
              height: 40.r,
              child: CircularProgressIndicator(
                color: AppColors.white,
                strokeWidth: 2.5,
                value: progress.expectedTotalBytes != null
                    ? (progress.cumulativeBytesLoaded /
                        progress.expectedTotalBytes!)
                    : null,
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined, color: Colors.white54, size: 40.r),
              Gap(8.h),
              Text(
                'Could not load this image.',
                style: AppTypography.bodySmall.copyWith(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
