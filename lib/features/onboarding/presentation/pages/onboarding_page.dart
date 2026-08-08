import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/design/design_system.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/services/storage_service.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  late PageController _pageController;
  int _currentIndex = 0;

  final List<_OnboardingItem> _slides = const [
    _OnboardingItem(
      image: 'assets/images/onboarding/onboarding_1.png',
      tagline: 'Care for every fabric. Trusted by thousands.',
    ),
    _OnboardingItem(
      image: 'assets/images/onboarding/onboarding_2.png',
      tagline: 'Wash, dry clean, iron and more — all in one app.',
    ),
    _OnboardingItem(
      image: 'assets/images/onboarding/onboarding_3.png',
      tagline: 'Compare vendors nearby and book the best fit.',
    ),
    _OnboardingItem(
      image: 'assets/images/onboarding/onboarding_4.png',
      tagline: 'Track pickup to delivery, every step of the way.',
    ),
    _OnboardingItem(
      image: 'assets/images/onboarding/onboarding_5.png',
      tagline: 'Ready whenever you are. Let\'s get started.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onNext() {
    if (_currentIndex < _slides.length - 1) {
      _pageController.nextPage(
        duration: AppDurations.normal,
        curve: AppCurves.standard,
      );
    } else {
      _finishOnboarding();
    }
  }

  void _finishOnboarding() async {
    final storage = ref.read(storageServiceProvider);
    await storage.saveBool(AppConstants.keyOnboardingDone, value: true);
    if (mounted) {
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Full-bleed background artwork, swipeable per slide.
          PageView.builder(
            controller: _pageController,
            onPageChanged: (idx) => setState(() => _currentIndex = idx),
            itemCount: _slides.length,
            itemBuilder: (context, index) {
              return Image.asset(
                _slides[index].image,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              );
            },
          ),

          // Skip button, floating over the artwork.
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: EdgeInsets.only(right: 8.w, top: 4.h),
                child: Material(
                  color: AppColors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(AppRadius.full.r),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.full.r),
                    onTap: _finishOnboarding,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                      child: Text(
                        'Skip',
                        style: AppTypography.labelLarge
                            .copyWith(color: AppColors.primary),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Bottom sheet-style control bar: tagline, dots, CTA.
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(
                AppSpacing.pagePaddingH.w,
                24.h,
                AppSpacing.pagePaddingH.w,
                16.h,
              ),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(AppRadius.sheet.r),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.textBlack.withValues(alpha: 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, -8),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.auto_awesome_rounded,
                            size: 18.r, color: AppColors.primary),
                        Gap(8.w),
                        Flexible(
                          child: Text(
                            _slides[_currentIndex].tagline,
                            style: AppTypography.bodyMedium.copyWith(
                              color: AppColors.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    Gap(16.h),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        _slides.length,
                        (index) => AnimatedContainer(
                          duration: AppDurations.fast,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: _currentIndex == index ? 24.w : 8.w,
                          height: 8.h,
                          decoration: BoxDecoration(
                            color: _currentIndex == index
                                ? AppColors.primary
                                : AppColors.outlineVariant,
                            borderRadius: BorderRadius.circular(AppRadius.full.r),
                          ),
                        ),
                      ),
                    ),
                    Gap(20.h),
                    SizedBox(
                      width: double.infinity,
                      child: AppButton(
                        label: _currentIndex == _slides.length - 1
                            ? 'Get Started'
                            : 'Next',
                        onPressed: _onNext,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingItem {
  const _OnboardingItem({
    required this.image,
    required this.tagline,
  });

  final String image;
  final String tagline;
}
