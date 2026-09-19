import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import '../theme/theme.dart';
import 'app_button.dart';

/// LNDRY Reusable Bottom Sheet modal templates.
/// Features a premium easeOutBack spring animation on entry.
class AppBottomSheet extends StatelessWidget {
  const AppBottomSheet({
    super.key,
    required this.title,
    required this.child,
    this.primaryActionLabel,
    this.onPrimaryAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.scrollableChild = false,
  });

  final String title;
  final Widget child;
  final String? primaryActionLabel;
  final VoidCallback? onPrimaryAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  /// When true, [child] is expected to scroll on its own (e.g. a shrink-wrapped
  /// `ListView`): the header and action buttons stay pinned and the sheet is
  /// height-capped so a long list scrolls inside it instead of being clipped.
  /// Only use with `isScrollControlled: true`.
  final bool scrollableChild;

  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required Widget child,
    String? primaryActionLabel,
    VoidCallback? onPrimaryAction,
    String? secondaryActionLabel,
    VoidCallback? onSecondaryAction,
    bool isScrollControlled = false,
    bool scrollableChild = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: isScrollControlled,
      backgroundColor:
          isDark ? AppColors.darkSurfaceContainer : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet.r),
        ),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _SpringSlideUpTransition(
          child: AppBottomSheet(
            title: title,
            primaryActionLabel: primaryActionLabel,
            onPrimaryAction: onPrimaryAction,
            secondaryActionLabel: secondaryActionLabel,
            onSecondaryAction: onSecondaryAction,
            scrollableChild: scrollableChild,
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final header = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            title,
            style: AppTypography.titleLarge,
          ),
        ),
        IconButton(
          icon: const Icon(AppIcons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );

    final actions = <Widget>[
      if (primaryActionLabel != null) ...[
        AppButton(
          label: primaryActionLabel!,
          onPressed: onPrimaryAction ?? () => Navigator.of(context).pop(),
        ),
        const Gap(12),
      ],
      if (secondaryActionLabel != null) ...[
        AppButton.outlined(
          label: secondaryActionLabel!,
          onPressed: onSecondaryAction ?? () => Navigator.of(context).pop(),
        ),
      ],
    ];

    final padding = EdgeInsets.symmetric(
      horizontal: AppSpacing.pagePaddingH.w,
      vertical: AppSpacing.pagePaddingV.h,
    );

    if (scrollableChild) {
      // Header and buttons stay pinned; only [child] scrolls, within a
      // height cap, so every item and the action buttons are always
      // reachable on any screen size.
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SafeArea(
          child: Padding(
            padding: padding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const Gap(16),
                Flexible(child: child),
                const Gap(24),
                ...actions,
              ],
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: padding,
        // A plain non-scrolling Column here overflows/garbles its layout
        // once the keyboard shrinks available height — e.g. a multi-line
        // comment field pushed the Submit button above the field it was
        // meant to sit under. Scrolling keeps everything reachable and in
        // order regardless of how much room the keyboard leaves.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const Gap(16),
              child,
              const Gap(24),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}

class _SpringSlideUpTransition extends StatefulWidget {
  final Widget child;
  const _SpringSlideUpTransition({required this.child});

  @override
  State<_SpringSlideUpTransition> createState() =>
      _SpringSlideUpTransitionState();
}

class _SpringSlideUpTransitionState extends State<_SpringSlideUpTransition>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _offsetAnimation,
      child: widget.child,
    );
  }
}
